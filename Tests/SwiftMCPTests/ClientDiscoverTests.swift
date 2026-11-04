import Testing
import Foundation
import SwiftMCP

/// A tiny in-process server for the client `discover()` round-trip.
@MCPServer(name: "ClientDiscoverServer", version: "3.0")
actor ClientDiscoverTestServer {
    /// Echoes its input.
    /// - Parameter text: The text to echo.
    /// - Returns: The same text.
    @MCPTool(description: "Echoes its input")
    func echo(text: String) -> String { text }
}

/// A tiny in-process server advertising `serverInstructions`, for the client
/// `initialize()` handshake round-trip.
@MCPServer(name: "ClientInstructionsServer", version: "1.0", instructions: "Always echo politely.")
actor ClientInstructionsTestServer {
    /// Echoes its input.
    /// - Parameter text: The text to echo.
    /// - Returns: The same text.
    @MCPTool(description: "Echoes its input")
    func echo(text: String) -> String { text }
}

@Suite("Client discover()")
struct ClientDiscoverTests {

    @Test("Client discover() returns and caches the server's DiscoverResult",
          .enabled(if: isStdioProcessSupported))
    func clientDiscover() async throws {
        let server = ClientDiscoverTestServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        let result = try await proxy.discover()
        #expect(result.supportedVersions.first == MCPProtocolVersion.modern)
        #expect(result.serverInfo.name == "ClientDiscoverServer")

        let cached = await proxy.lastDiscover
        #expect(cached?.supportedVersions == result.supportedVersions)
    }

    @Test("Client initialize() populates serverInstructions from the server's instructions",
          .enabled(if: isStdioProcessSupported))
    func clientServerInstructions() async throws {
        let server = ClientInstructionsTestServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        let instructions = await proxy.serverInstructions
        #expect(instructions == "Always echo politely.")
    }
}
