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

@Suite("Client discover()")
struct ClientDiscoverTests {

    @Test("Client discover() returns the server's supported versions and caches the result",
          .enabled(if: isStdioProcessSupported))
    func clientDiscover() async throws {
        let server = ClientDiscoverTestServer()
        let proxy = MCPServerProxy(config: .stdioHandles(server: server))
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        let discover = try await proxy.discover()
        #expect(discover.resultType == "complete")
        #expect(discover.supportedVersions == MCPProtocolVersion.supportedDescending)
        #expect(discover.serverInfo.name == "ClientDiscoverServer")
        #expect(discover.capabilities.tools != nil)

        let cached = await proxy.lastDiscover
        #expect(cached?.serverInfo.name == "ClientDiscoverServer")
    }
}
