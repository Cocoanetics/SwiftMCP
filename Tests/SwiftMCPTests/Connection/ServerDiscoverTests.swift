#if Server
import Testing
import Foundation
import Logging
@testable import SwiftMCP

/// A minimal server for exercising `server/discover` and the `-32004`
/// negotiation guard over the in-memory transport.
@MCPServer(name: "DiscoverTest", version: "2.0")
actor DiscoverTestServer {
    /// Echoes its input (gives the server a non-empty tools capability).
    /// - Parameter text: The text to echo.
    /// - Returns: The same text.
    @MCPTool(description: "Echoes its input")
    func echo(text: String) -> String { text }
}

@Suite("server/discover & -32004 negotiation")
struct ServerDiscoverTests {
    private static let logger = Logger(label: "test.discover")

    private func request(id: Int, method: String, params: JSONValue? = nil) -> JSONRPCMessage {
        .request(id: id, method: method, params: params)
    }

    private func initializeRequest(id: Int = 1) -> JSONRPCMessage {
        .request(id: id, method: "initialize", params: .object([
            "protocolVersion": .string("2025-11-25"),
            "capabilities": .object([:]),
            "clientInfo": .object(["name": .string("TestClient"), "version": .string("1.0")])
        ]))
    }

    /// Request params whose `_meta` carries a modern protocol version.
    private func metaVersion(_ version: String) -> JSONValue {
        .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string(version)])])
    }

    @Test("server/discover is answered before initialize and lists supported versions")
    func discoverBeforeInitialize() async throws {
        let server = DiscoverTestServer()
        let transport = InMemoryTransport()
        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()
        // No prior `initialize`: discover must still answer (pre-init exemption).
        connection.clientSends([request(id: 1, method: "server/discover")])

        let frame = try #require(await outbound.next())
        guard case .response(let response) = frame.first else {
            Issue.record("Expected a discover response, got \(String(describing: frame.first))")
            transport.stop()
            return
        }
        #expect(response.id == .integer(1))
        let result = try #require(response.result)
        let discover = try result.decoded(DiscoverResult.self)
        #expect(discover.resultType == "complete")
        #expect(discover.supportedVersions == MCPProtocolVersion.supportedDescending)
        #expect(discover.supportedVersions.first == "2025-11-25")   // newest first
        #expect(discover.serverInfo.name == "DiscoverTest")
        #expect(discover.capabilities.tools != nil)                 // the echo tool

        transport.stop()
        try await serveTask.value
    }

    @Test("An unsupported modern _meta protocolVersion is rejected with -32004")
    func unsupportedVersionYields32004() async throws {
        let server = DiscoverTestServer()
        let transport = InMemoryTransport()
        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([initializeRequest(id: 1)])
        _ = await outbound.next()   // initialize response

        connection.clientSends([request(id: 2, method: "ping", params: metaVersion("2099-01-01"))])
        let frame = try #require(await outbound.next())
        guard case .errorResponse(let err) = frame.first else {
            Issue.record("Expected a -32004 error, got \(String(describing: frame.first))")
            transport.stop()
            return
        }
        #expect(err.error.code == -32004)
        #expect(err.error.data?["requested"]?.stringValue == "2099-01-01")
        let supported = err.error.data?["supported"]?.arrayValue?.compactMap { $0.stringValue }
        #expect(supported == MCPProtocolVersion.supportedDescending)

        transport.stop()
        try await serveTask.value
    }

    @Test("server/discover still answers when carrying an unsupported _meta version")
    func discoverExemptFromGuard() async throws {
        let server = DiscoverTestServer()
        let transport = InMemoryTransport()
        let serveTask = Task {
            try await server.serve(over: [transport], gracefulShutdownSignals: [], logger: Self.logger)
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()
        connection.clientSends([request(id: 1, method: "server/discover", params: metaVersion("2099-01-01"))])

        let frame = try #require(await outbound.next())
        guard case .response = frame.first else {
            Issue.record("discover must answer despite an unsupported _meta version")
            transport.stop()
            return
        }
        transport.stop()
        try await serveTask.value
    }
}
#endif
