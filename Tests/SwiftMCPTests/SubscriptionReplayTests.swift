#if Server
// Verifies that MCPServerProxy tracks the desired subscription set locally and
// replays it automatically after any re-initialize, so callers never have to
// implement their own reconnect-and-resubscribe dance.

import Foundation
import Testing
import SwiftCross
@testable import SwiftMCP

@Suite("Subscription replay after re-initialize", .serialized)
struct SubscriptionReplayTests {

    // MARK: - Set management

    @Test("subscribeResource adds URI to local set")
    func subscribeAddsToSet() async throws {
        let server = PushFixtureServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        await proxy.setResourceNotificationHandler(PushRecorder())

        try await proxy.connect()
        let uri = URL(string: "push://status")!
        try await proxy.subscribeResource(uri: uri)

        let set = await proxy.subscribedResourceURIs
        #expect(set.contains(uri))

        await proxy.disconnect()
    }

    @Test("unsubscribeResource removes URI from local set")
    func unsubscribeRemovesFromSet() async throws {
        let server = PushFixtureServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        await proxy.setResourceNotificationHandler(PushRecorder())

        try await proxy.connect()
        let uri = URL(string: "push://status")!
        try await proxy.subscribeResource(uri: uri)
        try await proxy.unsubscribeResource(uri: uri)

        let set = await proxy.subscribedResourceURIs
        #expect(!set.contains(uri))

        await proxy.disconnect()
    }

    @Test("disconnect() clears the subscription set")
    func disconnectClearsSet() async throws {
        let server = PushFixtureServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        await proxy.setResourceNotificationHandler(PushRecorder())

        try await proxy.connect()
        let uri = URL(string: "push://status")!
        try await proxy.subscribeResource(uri: uri)

        let before = await proxy.subscribedResourceURIs
        #expect(before.contains(uri))

        await proxy.disconnect()

        let after = await proxy.subscribedResourceURIs
        #expect(after.isEmpty)
    }

    // MARK: - Replay on re-initialize (HTTP, macOS only)

    @Test("subscriptions are replayed on re-initialize", .timeLimit(.minutes(2)))
    func subscriptionsReplayedAfterReconnect() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport(
            server: PushFixtureServer()
        )
        defer { Task { try? await transport.stop() } }

        let mcpURL = baseURL.appendingPathComponent("mcp")
        let recorder = PushRecorder()
        let proxy = MCPServerProxy(config: .sse(config: MCPServerSseConfig(url: mcpURL)))
        await proxy.setResourceNotificationHandler(recorder)

        // First connection + subscribe
        try await proxy.connect(clientName: "test", clientVersion: "1.0")
        let uri = URL(string: "push://status")!
        try await proxy.subscribeResource(uri: uri)

        // Re-connect without disconnect — simulates session recovery
        try await proxy.connect(clientName: "test", clientVersion: "1.0")

        // Wait for the new session's general stream to establish
        try await Task.sleep(nanoseconds: 200_000_000)

        // Broadcast: the replayed subscription on the new session delivers it
        await transport.broadcastResourceUpdated(uri: uri)

        let received = await HTTPTransportTestHelpers.waitForCondition(
            timeoutNanoseconds: 5_000_000_000
        ) {
            recorder.count > 0
        }
        #expect(received, "Expected notification after subscription replay on re-initialize")

        await proxy.disconnect()
        #endif
    }
}
#endif
