#if Server
import Foundation
import Testing
@testable import SwiftMCP

@MCPServer(name: "SubscribeTestServer", version: "1.0")
actor SubscribeTestServer {
    let store: any MCPEventSubscriptionStore

    init(store: any MCPEventSubscriptionStore) {
        self.store = store
    }

    nonisolated var eventSubscriptionStore: any MCPEventSubscriptionStore { store }

    /// A build finished.
    ///
    /// - Parameter project: Only builds of this project.
    @MCPEvent(delivery: ["webhook"])
    func buildFinished(project: String? = nil) -> String { "" }

    /// A heartbeat.
    @MCPEvent(delivery: ["poll"])
    func heartbeat() -> String { "" }
}

@Suite("MCPEvent: subscription store and events/subscribe lifecycle")
struct MCPEventSubscriptionTests {

    private static let url = "https://example.com/hook"
    private let secret = WebhookSigner.generateSecret()

    private func makeStores() throws -> [(String, any MCPEventSubscriptionStore)] {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("events-\(UUID().uuidString).json")
        return [
            ("memory", MCPInMemoryEventSubscriptionStore()),
            ("file", try MCPFileEventSubscriptionStore(fileURL: file))
        ]
    }

    private func subscribeParams(
        name: String = "buildFinished",
        arguments: JSONValue = .object(["project": .string("A")]),
        url: String = MCPEventSubscriptionTests.url,
        secret: String?,
        ttlMs: Int? = nil
    ) throws -> JSONDictionary {
        try JSONDictionary(encoding: EventsSubscribeParams(
            name: name,
            arguments: arguments,
            delivery: EventsWebhookDelivery(url: url, secret: secret),
            ttlMs: ttlMs
        ))
    }

    private func send(
        _ server: any MCPServer,
        method: String,
        params: JSONDictionary,
        token: String? = nil
    ) async throws -> JSONRPCMessage {
        var params = params
        var meta: JSONDictionary = [MCPMetaKey.protocolVersion: .string("2026-07-28")]
        if let token { meta["accessToken"] = .string(token) }
        params["_meta"] = .object(meta)
        let message = JSONRPCMessage.request(id: 1, method: method, params: .object(params))
        return try #require(await RequestContext(message: message).work { _ in
            await server.handleMessage(message)
        })
    }

    private func subscribe(
        _ server: SubscribeTestServer,
        token: String? = nil,
        params: JSONDictionary
    ) async throws -> EventsSubscribeResult? {
        let response = try await send(server, method: "events/subscribe", params: params, token: token)
        guard case .response(let data) = response, let result = data.result else { return nil }
        return try result.decoded(EventsSubscribeResult.self)
    }

    private func errorCode(_ response: JSONRPCMessage) -> Int? {
        guard case .errorResponse(let error) = response else { return nil }
        return error.error.code
    }

    @Test("Subscribe is idempotent per key, principal-bound and unsubscribable (both stores)")
    func lifecycle() async throws {
        for (label, store) in try makeStores() {
            let server = SubscribeTestServer(store: store)
            let params = try subscribeParams(secret: secret)

            let first = try #require(try await subscribe(server, token: "alice", params: params), "\(label)")
            let again = try #require(try await subscribe(server, token: "alice", params: params), "\(label)")
            #expect(first.id == again.id, "\(label): same key keeps its id")
            #expect(first.refreshBefore != nil)
            #expect(first.deliveryStatus == nil)
            #expect(again.deliveryStatus?.active == true)

            let other = try #require(try await subscribe(server, token: "bob", params: params), "\(label)")
            #expect(other.id != first.id, "\(label): another principal gets its own record")
            let differentFilter = try #require(try await subscribe(
                server, token: "alice",
                params: try subscribeParams(arguments: .object(["project": .string("B")]), secret: secret)
            ))
            #expect(differentFilter.id != first.id)
            #expect(try await store.subscriptions(principal: "token:alice", now: Date()).count == 2)

            // Bob cannot remove Alice's subscription.
            let unsubscribe = try JSONDictionary(encoding: EventsUnsubscribeParams(
                name: "buildFinished",
                arguments: .object(["project": .string("A")]),
                delivery: EventsWebhookDelivery(url: Self.url)
            ))
            _ = try await send(server, method: "events/unsubscribe", params: unsubscribe, token: "bob")
            #expect(try await store.subscription(id: first.id, now: Date()) != nil, "\(label)")
            #expect(try await store.subscription(id: other.id, now: Date()) == nil, "\(label)")

            let response = try await send(server, method: "events/unsubscribe", params: unsubscribe, token: "alice")
            guard case .response = response else {
                Issue.record("\(label): expected unsubscribe result, got \(response)")
                continue
            }
            #expect(try await store.subscription(id: first.id, now: Date()) == nil, "\(label)")
            // Idempotent.
            let repeated = try await send(server, method: "events/unsubscribe", params: unsubscribe, token: "alice")
            guard case .response = repeated else {
                Issue.record("\(label): repeated unsubscribe should succeed")
                continue
            }
        }
    }

    @Test("Invalid filters, events, URLs, secrets and TTLs are rejected with -32602")
    func rejections() async throws {
        let server = SubscribeTestServer(store: MCPInMemoryEventSubscriptionStore())
        let cases: [(String, JSONDictionary)] = [
            ("unknown filter property",
             try subscribeParams(arguments: .object(["nope": .string("x")]), secret: secret)),
            ("wrong filter type", try subscribeParams(arguments: .object(["project": .integer(3)]), secret: secret)),
            ("non-object filter", try subscribeParams(arguments: .string("x"), secret: secret)),
            ("unknown event", try subscribeParams(name: "missing", secret: secret)),
            ("no webhook delivery", try subscribeParams(name: "heartbeat", arguments: .object([:]), secret: secret)),
            ("http url", try subscribeParams(url: "http://example.com/hook", secret: secret)),
            ("loopback url", try subscribeParams(url: "https://127.0.0.1/hook", secret: secret)),
            ("missing secret", try subscribeParams(secret: nil)),
            ("short secret", try subscribeParams(secret: "whsec_c2hvcnQ=")),
            ("non-positive ttl", try subscribeParams(secret: secret, ttlMs: 0))
        ]
        for (label, params) in cases {
            let response = try await send(server, method: "events/subscribe", params: params)
            #expect(errorCode(response) == -32602, "\(label): \(response)")
        }
    }

    @Test("events/subscribe is -32601 on a legacy revision")
    func legacy() async throws {
        let server = SubscribeTestServer(store: MCPInMemoryEventSubscriptionStore())
        let params = try subscribeParams(secret: secret)
        let message = JSONRPCMessage.request(id: 1, method: "events/subscribe", params: .object(params))
        let response = try #require(await RequestContext(message: message).work { _ in
            await server.handleMessage(message)
        })
        #expect(errorCode(response) == -32601)
    }

    @Test("TTL is capped, records expire, and renewal extends them (both stores)")
    func expiryAndRenewal() async throws {
        for (label, store) in try makeStores() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            func make(expires: Date) -> MCPEventSubscription {
                MCPEventSubscription(
                    principal: "alice", name: "buildFinished", arguments: .object([:]),
                    url: Self.url, secret: secret, createdAt: start, expiresAt: expires
                )
            }
            let created = try await store.upsert(make(expires: start.addingTimeInterval(60)), now: start)
            #expect(created.created, "\(label)")

            // Renew before expiry: same id, new expiry.
            let renewAt = start.addingTimeInterval(30)
            let renewed = try await store.upsert(make(expires: renewAt.addingTimeInterval(60)), now: renewAt)
            #expect(!renewed.created && renewed.subscription.id == created.subscription.id, "\(label)")

            let beforeLapse = renewAt.addingTimeInterval(59)
            #expect(try await store.subscription(id: created.subscription.id, now: beforeLapse) != nil)
            let lapsed = renewAt.addingTimeInterval(61)
            #expect(try await store.subscription(id: created.subscription.id, now: lapsed) == nil, "\(label)")
            #expect(try await store.subscriptions(principal: nil, now: lapsed).isEmpty, "\(label)")

            // Subscribing after expiry creates a fresh record.
            let fresh = try await store.upsert(make(expires: lapsed.addingTimeInterval(60)), now: lapsed)
            #expect(fresh.created && fresh.subscription.id != created.subscription.id, "\(label)")

            let purged = try await store.purgeExpired(now: lapsed.addingTimeInterval(120))
            #expect(purged.count == 1, "\(label)")
        }

        // The handler caps a suggested TTL at the server maximum.
        let server = SubscribeTestServer(store: MCPInMemoryEventSubscriptionStore())
        let result = try #require(try await subscribe(
            server, params: try subscribeParams(secret: secret, ttlMs: 10_000_000_000)
        ))
        let refreshBefore = try #require(result.refreshBefore.flatMap { ISO8601DateFormatter().date(from: $0) })
        #expect(refreshBefore.timeIntervalSinceNow <= 3601)
    }

    @Test("Revocation removes every subscription of a principal (both stores)")
    func revocation() async throws {
        for (label, store) in try makeStores() {
            let server = SubscribeTestServer(store: store)
            _ = try await subscribe(server, token: "alice", params: try subscribeParams(secret: secret))
            _ = try await subscribe(server, token: "bob", params: try subscribeParams(secret: secret))

            let removed = try await server.revokeEventSubscriptions(forPrincipal: "token:alice")
            #expect(removed.count == 1, "\(label)")
            #expect(try await store.subscriptions(principal: "token:alice", now: Date()).isEmpty, "\(label)")
            #expect(try await store.subscriptions(principal: "token:bob", now: Date()).count == 1, "\(label)")
        }
    }

    @Test("The file store survives a restart and keeps its file private")
    func filePersistence() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let now = Date()
        let store = try MCPFileEventSubscriptionStore(fileURL: file)
        let stored = try await store.upsert(
            MCPEventSubscription(
                principal: "alice", name: "buildFinished", arguments: .object(["project": .string("A")]),
                url: Self.url, secret: secret, createdAt: now, expiresAt: now.addingTimeInterval(600)
            ),
            now: now
        )

        let reopened = try MCPFileEventSubscriptionStore(fileURL: file)
        let loaded = try #require(try await reopened.subscription(id: stored.subscription.id, now: now))
        #expect(loaded.principal == "alice" && loaded.secret == secret)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        #expect((attributes[.posixPermissions] as? Int) == 0o600)
    }
}
#endif
