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

    @Test("Client discover() throws on the server's -32601 while no modern era is supported",
          .enabled(if: isStdioProcessSupported))
    func clientDiscover() async throws {
        let server = ClientDiscoverTestServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        // Until dual-era support (#137) adds a modern revision to
        // `MCPProtocolVersion.supported`, the server can't truthfully answer
        // `server/discover` and reports -32601 per its documented contract.
        await #expect(throws: (any Error).self) {
            try await proxy.discover()
        }

        let cached = await proxy.lastDiscover
        #expect(cached == nil)
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
