#if Server
import Foundation
import Testing
@testable import SwiftMCP

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
        let sawFirst = HTTPTransportBox(false)
        let receiver = try LocalWebhookReceiver { number, _ in
            if number == 1 {
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

        let task = Task { try await emitBuild(server) }
        while !sawFirst.value { try await Task.sleep(nanoseconds: 10_000_000) }
        let removed = try await server.revokeEventSubscriptions(forPrincipal: "token:bob")
        #expect(removed.contains { $0.id == secondId })
        releaseFirst.modify { $0 = true }

        let outcomes = try await task.value
        #expect(outcomes.count == 2)
        let byId = Dictionary(uniqueKeysWithValues: outcomes.map { ($0.subscriptionId, $0) })
        #expect(byId[firstId]?.status == .delivered)
        #expect(byId[secondId]?.status == .failed)
        #expect(byId[secondId]?.error == "subscription inactive")
        #expect(byId[secondId]?.attempts == 0)
        #expect(receiver.requests.count == 1)
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
