import Testing
import Foundation
import Logging
@testable import SwiftMCP

// swiftlint:disable identifier_name
// Parameter names `a`, `b` mirror the canonical MCP calculator example.

/// A stateless value-type server — the case `@MCPServer` now supports directly.
/// With no shared mutable state, a `struct` is the natural (and trivially
/// `Sendable`) choice.
@MCPServer(name: "StructCalc", version: "2.0")
struct StructCalculator {
    /// Adds two integers and returns their sum.
    /// - Parameter a: First addend.
    /// - Parameter b: Second addend.
    /// - Returns: The sum of `a` and `b`.
    @MCPTool(description: "Adds two integers")
    func add(a: Int, b: Int) -> Int {
        a + b
    }
}

/// A value-type server that also receives an `@MCPExtension`. This exercises the
/// reference-boxed extension storage, which keeps `__mcpRegisterExtension`
/// non-`mutating` so `register(in:)` can install it on the immutable `server`.
@MCPServer(name: "StructWithExtension")
struct StructExtensionServer {
    /// A base tool declared on the primary type.
    @MCPTool
    func base(a: Int) -> Int {
        a
    }
}

@MCPExtension("StructMath")
extension StructExtensionServer {
    /// Multiplies two integers.
    @MCPTool
    func multiply(a: Int, b: Int) -> Int {
        a * b
    }
}

@Suite("Struct @MCPServer")
struct StructServerTests {
    @Test("A struct server carries its identity and tool metadata")
    func exposesMetadata() {
        let server = StructCalculator()
        #expect(server.serverName == "StructCalc")
        #expect(server.serverVersion == "2.0")
        #expect(server.mcpToolMetadata.contains { $0.name == "add" })
    }

    @Test("A struct server runs a tool")
    func runsTool() async throws {
        let server = StructCalculator()
        let result = try await server.callTool("add", arguments: ["a": .integer(2), "b": .integer(3)])
        #expect((result as? Int) == 5)
    }

    @Test("A struct server is trivially Sendable")
    func isSendable() {
        // Compiles only if `StructCalculator` conforms to `Sendable`.
        func requireSendable<T: Sendable>(_ value: T) -> T { value }
        _ = requireSendable(StructCalculator())
    }

    @Test("A struct server accepts @MCPExtension registration")
    func acceptsExtension() async throws {
        let server = StructExtensionServer()
        #expect(server.mcpToolMetadata.contains { $0.name == "base" })
        #expect(!server.mcpToolMetadata.contains { $0.name == "multiply" })

        // Must compile and take effect even though `server` is an immutable
        // value — the contributions live in a reference box.
        await StructExtensionServer.StructMath.register(in: server)

        #expect(server.mcpToolMetadata.contains { $0.name == "multiply" })
        let product = try await server.callTool("multiply", arguments: ["a": 6, "b": 7])
        #expect(product as? Int == 42)
    }

    #if Server
    @Test("A struct server can be served over a transport")
    func servesOverTransport() async throws {
        let server = StructCalculator()
        let transport = InMemoryTransport()

        let serveTask = Task {
            try await server.serve(
                over: [transport],
                gracefulShutdownSignals: [],
                logger: .init(label: "test.struct.serve")
            )
        }

        let connection = transport.accept()
        var outbound = connection.outbound.makeAsyncIterator()

        connection.clientSends([
            .request(
                id: 1,
                method: "initialize",
                params: [
                    "protocolVersion": .string("2025-06-18"),
                    "capabilities": .object([:]),
                    "clientInfo": .object(["name": .string("Test"), "version": .string("1.0")])
                ]
            )
        ])
        _ = await outbound.next()   // initialize response

        connection.clientSends([
            .request(
                id: 2,
                method: "tools/call",
                params: [
                    "name": .string("add"),
                    "arguments": .object(["a": .integer(40), "b": .integer(2)])
                ]
            )
        ])

        let frame = try #require(await outbound.next())
        guard case .response(let response) = frame.first else {
            Issue.record("Expected a tool-call response, got \(String(describing: frame.first))")
            transport.stop()
            return
        }
        #expect(response.id == .integer(2))
        let encoded = try JSONEncoder().encode(response.result)
        #expect(String(data: encoded, encoding: .utf8)?.contains("42") == true)

        transport.stop()
        try await serveTask.value
    }
    #endif
}
// swiftlint:enable identifier_name
