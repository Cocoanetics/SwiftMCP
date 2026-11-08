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
    private func digest(_ principal: String) -> String { SubscribeTestServer.eventPrincipalDigest(principal) }
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
        token: String? = "alice"
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
        token: String? = "alice",
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
            #expect(try await store.subscriptions(principal: digest("token:alice"), now: Date()).count == 2)

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
            #expect(try await store.subscriptions(principal: digest("token:alice"), now: Date()).isEmpty, "\(label)")
            #expect(try await store.subscriptions(principal: digest("token:bob"), now: Date()).count == 1, "\(label)")
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

    @Test("A refresh without a cursor clears the stored one (both stores)")
    func refreshClearsCursor() async throws {
        for (label, store) in try makeStores() {
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            func make(cursor: String?) -> MCPEventSubscription {
                MCPEventSubscription(
                    principal: "alice", name: "buildFinished", arguments: .object([:]), url: Self.url,
                    secret: secret, createdAt: now, expiresAt: now.addingTimeInterval(600), cursor: cursor
                )
            }
            _ = try await store.upsert(make(cursor: "c1"), now: now)
            let refreshed = try await store.upsert(make(cursor: nil), now: now)
            #expect(refreshed.subscription.cursor == nil, "\(label)")
        }
    }

    @Test("A failed file save leaves the in-memory state unchanged")
    func failedSaveIsNotCommitted() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let store = try MCPFileEventSubscriptionStore(fileURL: directory.appendingPathComponent("subs.json"))
        let now = Date()
        let subscription = MCPEventSubscription(
            principal: "alice", name: "buildFinished", arguments: .object([:]), url: Self.url,
            secret: secret, createdAt: now, expiresAt: now.addingTimeInterval(600)
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        guard (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) != nil,
              !FileManager.default.isWritableFile(atPath: directory.path) else {
            return // running as a user that ignores directory permissions
        }
        await #expect(throws: (any Error).self) { try await store.upsert(subscription, now: now) }
        #expect(try await store.subscriptions(principal: nil, now: now).isEmpty)
    }

}

extension MCPEventSubscriptionTests {
    @Test("Anonymous callers cannot subscribe or unsubscribe")
    func anonymousRejected() async throws {
        let server = SubscribeTestServer(store: MCPInMemoryEventSubscriptionStore())
        let subscribe = try await send(server, method: "events/subscribe",
                                       params: try subscribeParams(secret: secret), token: nil)
        #expect(errorCode(subscribe) == -32600)
        let unsubscribe = try JSONDictionary(encoding: EventsUnsubscribeParams(
            name: "buildFinished", arguments: .object(["project": .string("A")]),
            delivery: EventsWebhookDelivery(url: Self.url)
        ))
        let response = try await send(server, method: "events/unsubscribe", params: unsubscribe, token: nil)
        #expect(errorCode(response) == -32600)
    }

    @Test("Stored principals are digests: no bearer token reaches the store or its file")
    func principalIsDigested() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("events-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let server = SubscribeTestServer(store: try MCPFileEventSubscriptionStore(fileURL: file))
        _ = try await subscribe(server, token: "super-secret-token", params: try subscribeParams(secret: secret))
        let contents = try String(contentsOf: file, encoding: .utf8)
        #expect(!contents.contains("super-secret-token"))
        #expect(contents.contains(digest("token:super-secret-token")))
    }

    @Test("Servers without an explicit store do not share subscriptions")
    func defaultStoresAreIsolated() async throws {
        let first = DefaultStoreServer()
        let second = DefaultStoreServer()
        let now = Date()
        _ = try await first.eventSubscriptionStore.upsert(
            MCPEventSubscription(principal: "p", name: "heartbeat", arguments: .object([:]), url: Self.url,
                                 secret: secret, createdAt: now, expiresAt: now.addingTimeInterval(60)),
            now: now
        )
        #expect(try await first.eventSubscriptionStore.subscriptions(principal: nil, now: now).count == 1)
        #expect(try await second.eventSubscriptionStore.subscriptions(principal: nil, now: now).isEmpty)
        #expect(try await first.eventSubscriptionStore.subscriptions(principal: nil, now: now).count == 1)
    }

    @Test("Writes drop lapsed records so they cannot accumulate (both stores)")
    func upsertPurgesLapsed() async throws {
        for (label, store) in try makeStores() {
            let start = Date(timeIntervalSince1970: 1_800_000_000)
            for index in 0..<3 {
                _ = try await store.upsert(
                    MCPEventSubscription(principal: "p\(index)", name: "buildFinished", arguments: .object([:]),
                                         url: Self.url, secret: secret, createdAt: start,
                                         expiresAt: start.addingTimeInterval(60)),
                    now: start
                )
            }
            let later = start.addingTimeInterval(120)
            _ = try await store.upsert(
                MCPEventSubscription(principal: "p9", name: "buildFinished", arguments: .object([:]),
                                     url: Self.url, secret: secret, createdAt: later,
                                     expiresAt: later.addingTimeInterval(60)),
                now: later
            )
            // Nothing lapsed is left to purge: only the fresh record remains.
            #expect(try await store.purgeExpired(now: later.addingTimeInterval(3600)).count == 1, "\(label)")
        }
    }
}

actor DefaultStoreServer: MCPServer, MCPEventProviding {
    var mcpEventMetadata: [MCPEventMetadata] { [] }
}
#endif
