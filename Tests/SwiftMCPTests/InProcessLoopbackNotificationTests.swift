import Foundation
import Testing
import SwiftMCP

/// A server whose tool captures `Session.current`, so a test can send
/// notifications through that session after the request has finished.
@MCPServer(name: "LoopbackNotificationServer", version: "1.0.0")
private actor LoopbackNotificationServer {
    private(set) var savedSession: Session?

    /// A subscribable resource, so `resources/subscribe` is accepted.
    @MCPResource("loopback://status")
    func status() -> String {
        "ok"
    }

    /// Captures the calling session.
    @MCPTool
    func saveSession() -> String {
        savedSession = Session.current
        return "saved"
    }
}

/// Records every notification the proxy hands its handlers, in arrival order.
private final class NotificationRecorder: MCPServerProxyResourceNotificationHandling,
    MCPServerProxyToolsListChangedHandling,
    MCPServerProxyResourcesListChangedHandling,
    MCPServerProxyPromptsListChangedHandling,
    @unchecked Sendable {
    let events: AsyncStream<String>
    private let continuation: AsyncStream<String>.Continuation

    init() {
        (events, continuation) = AsyncStream.makeStream()
    }

    func mcpServerProxy(_ proxy: MCPServerProxy, resourceUpdatedAt uri: URL) async {
        continuation.yield("updated \(uri.absoluteString)")
    }

    func mcpServerProxyToolsListDidChange(_ proxy: MCPServerProxy) async {
        continuation.yield("tools")
    }

    func mcpServerProxyResourcesListDidChange(_ proxy: MCPServerProxy) async {
        continuation.yield("resources")
    }

    func mcpServerProxyPromptsListDidChange(_ proxy: MCPServerProxy) async {
        continuation.yield("prompts")
    }
}

struct InProcessLoopbackNotificationTests {
    @Test("STDIO in-process: a captured session delivers notifications outside a request",
          .timeLimit(.minutes(1)))
    func capturedSessionDeliversNotifications() async throws {
        let server = LoopbackNotificationServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        let recorder = NotificationRecorder()
        await proxy.setResourceNotificationHandler(recorder)
        await proxy.setToolsListChangedHandler(recorder)
        await proxy.setResourcesListChangedHandler(recorder)
        await proxy.setPromptsListChangedHandler(recorder)
        try await proxy.connect()

        let uri = try #require(URL(string: "loopback://status"))
        try await proxy.subscribeResource(uri: uri)
        _ = try await proxy.callTool("saveSession")
        let session = try #require(await server.savedSession)

        try await session.work { session in
            try await session.sendResourceUpdated(uri: uri)
            try await session.sendToolListChanged()
            try await session.sendResourceListChanged()
            try await session.sendPromptListChanged()
        }

        var received: [String] = []
        for await event in recorder.events {
            received.append(event)
            if received.count == 4 { break }
        }
        #expect(Set(received) == ["updated loopback://status", "tools", "resources", "prompts"])

        await proxy.disconnect()
    }
}
