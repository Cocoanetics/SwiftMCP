import Testing
import SwiftCross
@testable import SwiftMCP

@Suite("MCPServerProxy Streamable HTTP")
struct MCPServerProxyStreamableHTTPTests {
    private func startTransport(server: some MCPServer = Calculator()) async throws -> (HTTPSSETransport, URL) {
        let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
        try await transport.start()
        let baseURL = URL(string: "http://127.0.0.1:\(transport.port)/mcp")!
        return (transport, baseURL)
    }

    @Test("Proxy connects to streamable HTTP and can ping/list tools")
    func connectAndPing() async throws {
        let (transport, url) = try await startTransport()
        defer { Task { try? await transport.stop() } }

        let proxy = MCPServerProxy(config: .sse(config: MCPServerSseConfig(url: url)))
        defer { Task { await proxy.disconnect() } }

        try await proxy.connect()
        let serverName = await proxy.serverName
        #expect(serverName == "Calculator")

        try await proxy.ping()
        let tools = try await proxy.listTools()
        #expect(!tools.isEmpty)
    }

    @Test("Proxy receives list-changed notifications over the general GET stream")
    func receivesToolsListChanged() async throws {
        let (transport, url) = try await startTransport()
        defer { Task { try? await transport.stop() } }

        let handler = ToolsListChangedCapture()
        let proxy = MCPServerProxy(config: .sse(config: MCPServerSseConfig(url: url)))
        await proxy.setToolsListChangedHandler(handler)
        defer { Task { await proxy.disconnect() } }

        try await proxy.connect()
        let sessionID = try #require(await proxy.sessionID)
        let sessionUUID = try #require(UUID(uuidString: sessionID))
        let generalStreamReady = await waitForCondition {
            await transport.sessionManager.hasActivePrimaryGeneralConnection(for: sessionUUID)
        }
        #expect(generalStreamReady)
        await transport.broadcastToolsListChanged()

        let delivered = await waitForCondition {
            await handler.count > 0
        }
        #expect(delivered)
    }

    @Test("Tool call after the server forgets the session throws sessionInvalidated and keeps the session ID")
    func sessionInvalidationSurfacesTypedError() async throws {
        let (transport, url) = try await startTransport()
        defer { Task { try? await transport.stop() } }

        let proxy = MCPServerProxy(config: .sse(config: MCPServerSseConfig(url: url)))
        defer { Task { await proxy.disconnect() } }

        try await proxy.connect()
        let sessionID = try #require(await proxy.sessionID)
        let sessionUUID = try #require(UUID(uuidString: sessionID))

        // Simulate a server restart wiping its in-memory session table: the
        // session UUID the client still holds is no longer known to the server.
        await transport.sessionManager.removeSession(id: sessionUUID)

        // A subsequent request must surface a typed `.sessionInvalidated` error
        // rather than spinning or returning a generic communication error. (#125)
        do {
            try await proxy.ping()
            Issue.record("Expected ping to throw after the session was invalidated")
        } catch let error as MCPServerProxyError {
            guard case .sessionInvalidated = error else {
                Issue.record("Expected .sessionInvalidated, got \(error)")
                return
            }
        }

        // The 404 must NOT have wiped the stale-but-present session ID, so the
        // header keeps being attached and the application retains the context it
        // needs to decide how to reconnect.
        let retainedSessionID = await proxy.sessionID
        #expect(retainedSessionID == sessionID)
    }

    private func waitForCondition(
        timeoutNanoseconds: UInt64 = 2_000_000_000,
        pollNanoseconds: UInt64 = 50_000_000,
        _ condition: @escaping @Sendable () async -> Bool
    ) async -> Bool {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if await condition() {
                return true
            }
            try? await Task.sleep(nanoseconds: pollNanoseconds)
        }
        return await condition()
    }
}

private actor ToolsListChangedCapture: MCPServerProxyToolsListChangedHandling {
    private(set) var count = 0

    func mcpServerProxyToolsListDidChange(_ proxy: MCPServerProxy) async {
        count += 1
    }
}
