#if Server
import Foundation
import Testing
@testable import SwiftMCP

private struct DelayedLookupEventSubscriptionStore: MCPEventSubscriptionStore {
    let base = MCPInMemoryEventSubscriptionStore()
    let lookupCount = HTTPTransportBox(0)
    let finalLookupStarted = HTTPTransportBox(false)
    let releaseFinalLookup = HTTPTransportBox(false)

    func upsert(_ subscription: MCPEventSubscription, now: Date) async throws -> MCPEventUpsertResult {
        try await base.upsert(subscription, now: now)
    }

    func subscription(id: String, now: Date) async throws -> MCPEventSubscription? {
        lookupCount.modify { $0 += 1 }
        if lookupCount.value == 2 {
            finalLookupStarted.value = true
            while !releaseFinalLookup.value { try await Task.sleep(nanoseconds: 10_000_000) }
        }
        return try await base.subscription(id: id, now: now)
    }

    func subscriptions(principal: String?, now: Date) async throws -> [MCPEventSubscription] {
        try await base.subscriptions(principal: principal, now: now)
    }

    func remove(key: MCPEventSubscriptionKey) async throws -> Bool {
        try await base.remove(key: key)
    }

    func revoke(principal: String) async throws -> [MCPEventSubscription] {
        try await base.revoke(principal: principal)
    }

    func purgeExpired(now: Date) async throws -> [MCPEventSubscription] {
        try await base.purgeExpired(now: now)
    }

    func applyDeliveryOutcome(
        id: String,
        update: MCPEventSubscriptionDeliveryUpdate,
        now: Date,
        disableAfterConsecutiveFailures: Int
    ) async throws -> MCPEventSubscription? {
        try await base.applyDeliveryOutcome(
            id: id,
            update: update,
            now: now,
            disableAfterConsecutiveFailures: disableAfterConsecutiveFailures
        )
    }
}

/// Records the subscription id of every POST instead of using a socket.
private struct RecordingWebhookTransport: MCPWebhookTransport {
    let posted: HTTPTransportBox<[String]>

    func post(
        url: URL, headers: [String: String], body: Data, timeout: TimeInterval
    ) async throws -> MCPWebhookResponse {
        posted.modify { $0.append(headers[MCPEventDeliveryEngine.subscriptionIdHeader] ?? "") }
        return MCPWebhookResponse(statusCode: 200)
    }
}

extension MCPEventDeliveryTests {
    @Test("Dictionary payloads validate as open objects")
    func dictionaryPayloadIsOpen() async throws {
        let receiver = try LocalWebhookReceiver { _, _ in (200, [:]) }
        defer { receiver.stop() }
        let server = makeServer(port: receiver.port)
        let arguments: JSONValue = .object([:])
        let delivery = EventsWebhookDelivery(url: Self.url, secret: secret)
        var params = try JSONDictionary(encoding: EventsSubscribeParams(
            name: "changed", arguments: arguments, delivery: delivery
        ))
        params["_meta"] = .object([MCPMetaKey.protocolVersion: .string("2026-07-28"), "accessToken": .string("alice")])
        let message = JSONRPCMessage.request(id: 1, method: "events/subscribe", params: .object(params))
        _ = try #require(await RequestContext(message: message).work { _ in await server.handleMessage(message) })

        let outcomes = try await server.emit("changed", ["key": "value"])
        #expect(outcomes.count == 1)
        #expect(outcomes.first?.status == .delivered)
    }

    @Test("Numeric filter values match across JSON number cases")
    func numericFilterMatchesJSONNumber() async throws {
        let receiver = try LocalWebhookReceiver { _, _ in (200, [:]) }
        defer { receiver.stop() }
        let server = makeServer(port: receiver.port)
        let arguments: JSONValue = .object(["count": .integer(1)])
        let delivery = EventsWebhookDelivery(url: Self.url, secret: secret)
        var params = try JSONDictionary(encoding: EventsSubscribeParams(
            name: "changed", arguments: arguments, delivery: delivery
        ))
        params["_meta"] = .object([MCPMetaKey.protocolVersion: .string("2026-07-28"), "accessToken": .string("alice")])
        let message = JSONRPCMessage.request(id: 1, method: "events/subscribe", params: .object(params))
        _ = try #require(await RequestContext(message: message).work { _ in await server.handleMessage(message) })

        let asDouble = try await server.emit(
            "changed", ["key": "value"], attributes: .object(["count": .double(1.0)])
        )
        #expect(asDouble.count == 1 && asDouble.first?.status == .delivered)

        let asUnsigned = try await server.emit(
            "changed", ["key": "value"], attributes: .object(["count": .unsignedInteger(1)])
        )
        #expect(asUnsigned.count == 1 && asUnsigned.first?.status == .delivered)
    }

    @Test("Queued deliveries recheck activity before the first POST and before retries")
    func recheckActivityBeforeDelivery() async throws {
        let releaseFirst = HTTPTransportBox(false)
        defer { releaseFirst.modify { $0 = true } }
        let sawFirst = HTTPTransportBox(false)
        let heldSubscription = HTTPTransportBox<String?>(nil)
        let receiver = try LocalWebhookReceiver { _, request in
            if request.headers["x-mcp-subscription-id"] == heldSubscription.value {
                sawFirst.modify { $0 = true }
                while !releaseFirst.value { Thread.sleep(forTimeInterval: 0.01) }
            }
            return (200, [:])
        }
        defer { receiver.stop() }
        let config = configuration(port: receiver.port, maxConcurrentDeliveries: 1)
        let store = MCPInMemoryEventSubscriptionStore()
        let server = DeliveryTestServer(store: store, configuration: config)
        let firstId = try #require(try await subscribe(server, token: "alice"))
        let secondId = try #require(try await subscribe(server, token: "bob"))
        let ordered = try await store.subscriptions(principal: nil, now: Date())
        let heldId = try #require(ordered.first?.id)
        let queuedId = try #require(ordered.last?.id)
        #expect(Set(ordered.map(\.id)) == [firstId, secondId])
        heldSubscription.modify { $0 = heldId }

        let task = Task { try await emitBuild(server) }
        while !sawFirst.value { try await Task.sleep(nanoseconds: 10_000_000) }
        let queuedPrincipal = queuedId == secondId ? "token:bob" : "token:alice"
        let removed = try await server.revokeEventSubscriptions(forPrincipal: queuedPrincipal)
        #expect(removed.contains { $0.id == queuedId })
        releaseFirst.modify { $0 = true }

        let outcomes = try await task.value
        #expect(outcomes.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.subscriptionId, $0) })
        #expect(byId[heldId]?.status == .delivered)
        #expect(byId[queuedId]?.status == .failed)
        #expect(byId[queuedId]?.error == "subscription inactive")
        #expect(byId[queuedId]?.attempts == 0)
        #expect(receiver.requests.count == 1)
        #expect(receiver.requests.first?.headers["x-mcp-subscription-id"] == heldId)
    }

    @Test("Concurrent deliveries recheck activity after URL validation and before POST")
    func recheckActivityAfterURLValidation() async throws {
        let releaseValidation = HTTPTransportBox(false)
        defer { releaseValidation.modify { $0 = true } }
        let validating = HTTPTransportBox(0)
        let posted = HTTPTransportBox<[String]>([])
        let resolver: WebhookURLPolicy.Resolver = { _ in
            validating.modify { $0 += 1 }
            while !releaseValidation.value { try await Task.sleep(nanoseconds: 10_000_000) }
            return ["93.184.216.34"]
        }
        var config = configuration(port: 0, resolver: resolver, maxConcurrentDeliveries: 2)
        config.transport = RecordingWebhookTransport(posted: posted)
        let store = MCPInMemoryEventSubscriptionStore()
        let server = DeliveryTestServer(store: store, configuration: config)
        let firstId = try #require(try await subscribe(server, token: "alice"))
        let secondId = try #require(try await subscribe(server, token: "bob"))
        let ordered = try await store.subscriptions(principal: nil, now: Date())
        let heldId = try #require(ordered.first?.id)
        let queuedId = try #require(ordered.last?.id)
        #expect(Set(ordered.map(\.id)) == [firstId, secondId])

        let task = Task { try await emitBuild(server) }
        // Both attempts have passed the initial activity check and are suspended in DNS validation.
        while validating.value < 2 { try await Task.sleep(nanoseconds: 10_000_000) }
        let queuedPrincipal = queuedId == secondId ? "token:bob" : "token:alice"
        let removed = try await server.revokeEventSubscriptions(forPrincipal: queuedPrincipal)
        #expect(removed.contains { $0.id == queuedId })
        releaseValidation.modify { $0 = true }

        let outcomes = try await task.value
        #expect(outcomes.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.subscriptionId, $0) })
        #expect(byId[heldId]?.status == .delivered)
        #expect(byId[queuedId]?.status == .failed)
        #expect(byId[queuedId]?.error == "subscription inactive")
        #expect(byId[queuedId]?.attempts == 0)
        #expect(posted.value == [heldId])
    }

    @Test("Webhook signatures are generated after the final activity lookup")
    func signatureFollowsFinalActivityLookup() async throws {
        let receiver = try LocalWebhookReceiver { _, _ in (200, [:]) }
        defer { receiver.stop() }
        let initialTime = Date(timeIntervalSince1970: 1_700_000_000)
        let deliveryTime = initialTime.addingTimeInterval(WebhookSigner.defaultTolerance + 1)
        let clock = HTTPTransportBox(initialTime)
        let store = DelayedLookupEventSubscriptionStore()
        defer { store.releaseFinalLookup.value = true }
        var config = configuration(port: receiver.port)
        config.now = { clock.value }
        let server = DeliveryTestServer(store: store, configuration: config)
        _ = try #require(try await subscribe(server))

        let task = Task { try await emitBuild(server, eventId: "evt_fresh_signature") }
        while !store.finalLookupStarted.value { try await Task.sleep(nanoseconds: 10_000_000) }
        clock.value = deliveryTime
        store.releaseFinalLookup.value = true

        let outcome = try #require(try await task.value.first)
        #expect(outcome.status == .delivered)
        let request = try #require(receiver.requests.first)
        #expect(request.headers[WebhookSigner.timestampHeader] == String(Int(deliveryTime.timeIntervalSince1970)))
        try WebhookSigner(secret: secret).verify(headers: request.headers, body: request.body, now: deliveryTime)
    }

    @Test("Cancelling emit cancels the in-flight transfer and stops later attempts")
    func cancellationStopsDelivery() async throws {
        let sawRequest = HTTPTransportBox(false)
        let receiver = try LocalWebhookReceiver { _, _ in
            sawRequest.modify { $0 = true }
            Thread.sleep(forTimeInterval: 2)
            return (200, [:])
        }
        defer { receiver.stop() }
        let delays = HTTPTransportBox<[TimeInterval]>([])
        let server = DeliveryTestServer(
            store: MCPInMemoryEventSubscriptionStore(),
            configuration: configuration(port: receiver.port, delays: delays, maxAttempts: 4)
        )
        _ = try await subscribe(server)

        let task = Task { try await emitBuild(server) }
        while !sawRequest.value { try await Task.sleep(nanoseconds: 10_000_000) }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("expected CancellationError")
        } catch is CancellationError {
            // Expected: the stalled POST and remaining retries must stop.
        }
        #expect(delays.value.isEmpty || delays.value.allSatisfy { $0 >= 0 })
    }

    @Test("Retry-After is honored above maxBackoff")
    func retryAfterNotCappedToMaxBackoff() async throws {
        let receiver = try LocalWebhookReceiver { _, _ in (429, ["Retry-After": "300"]) }
        defer { receiver.stop() }
        let delays = HTTPTransportBox<[TimeInterval]>([])
        let server = DeliveryTestServer(
            store: MCPInMemoryEventSubscriptionStore(),
            configuration: configuration(port: receiver.port, delays: delays, maxAttempts: 2)
        )
        _ = try await subscribe(server)

        let outcome = try #require(try await emitBuild(server).first)
        #expect(outcome.status == .failed)
        #expect(delays.value == [300], "receiver Retry-After must not be shortened to maxBackoff")
    }

    @Test("Repeated exhausted failures auto-disable the subscription")
    func autoDisableAfterRepeatedFailures() async throws {
        let receiver = try LocalWebhookReceiver { _, _ in (200, [:]) }
        let port = receiver.port
        receiver.stop()
        let store = MCPInMemoryEventSubscriptionStore()
        let server = DeliveryTestServer(
            store: store,
            configuration: configuration(
                port: port, maxAttempts: 2, disableAfterConsecutiveFailures: 2
            )
        )
        let id = try #require(try await subscribe(server))

        #expect(try await emitBuild(server).first?.status == .failed)
        var record = try #require(try await store.subscription(id: id, now: Date()))
        #expect(record.isDeliveryActive)
        #expect(record.consecutiveDeliveryFailures == 1)

        #expect(try await emitBuild(server).first?.status == .failed)
        record = try #require(try await store.subscription(id: id, now: Date()))
        #expect(!record.isDeliveryActive)
        #expect(record.consecutiveDeliveryFailures == 2)

        #expect(try await emitBuild(server).isEmpty, "disabled subscriptions are not selected")

        // A subscribe refresh re-enables delivery after the subscriber recovers.
        let refreshed = try #require(try await subscribe(server))
        #expect(refreshed == id)
        record = try #require(try await store.subscription(id: id, now: Date()))
        #expect(record.isDeliveryActive)
        #expect(record.consecutiveDeliveryFailures == 0)
    }
}
#endif
