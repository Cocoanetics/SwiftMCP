import Foundation
import Testing
@testable import SwiftMCP
@testable import SwiftMCPUtilityCore

/// Parameters named like the generated client's own locals. The generated
/// `Client` used to declare `var arguments: JSONDictionary` and
/// `let capturedArguments`, which shadowed these parameters and sent `{}` (#274).
/// The locals are now named per method so they avoid every parameter name,
/// including their own default names.
@MCPServer(name: "Reserved Names Fixture", version: "1")
final class ReservedNamesFixtureServer: Sendable {
    /// Counts the arguments.
    @MCPTool
    func count(arguments: [String] = []) -> Int {
        arguments.count
    }

    /// Counts the arguments asynchronously.
    @MCPTool
    func countAsync(arguments: [String] = []) async -> Int {
        arguments.count
    }

    /// Joins the captured arguments.
    @MCPTool
    func join(capturedArguments: [String], arguments: [String]) -> String {
        (capturedArguments + arguments).joined(separator: ",")
    }

    /// Joins parameters named like the generated locals' default names.
    @MCPTool
    // swiftlint:disable:next identifier_name
    func joinReserved(__mcpArguments: [String], __mcpCapturedArguments: String? = nil) -> String {
        (__mcpArguments + [__mcpCapturedArguments ?? "-"]).joined(separator: ",")
    }
}

@Suite("Client reserved parameter names")
struct ClientReservedParameterNameTests {

    private func makeClient() async throws -> (MCPServerProxy, ReservedNamesFixtureServer.Client) {
        let proxy = MCPServerProxy(config: .stdioHandles(server: ReservedNamesFixtureServer()))
        try await proxy.connect(clientName: "reserved-names", clientVersion: "1")
        return (proxy, ReservedNamesFixtureServer.Client(proxy: proxy))
    }

    @Test("a synchronous tool parameter named `arguments` reaches the server")
    func syncToolArguments() async throws {
        let (proxy, client) = try await makeClient()
        defer { Task { await proxy.disconnect() } }
        #expect(try client.count(arguments: ["a"]) == 1)
    }

    @Test("an async tool parameter named `arguments` reaches the server")
    func asyncToolArguments() async throws {
        let (proxy, client) = try await makeClient()
        defer { Task { await proxy.disconnect() } }
        #expect(try await client.countAsync(arguments: ["a", "b"]) == 2)
    }

    @Test("a tool parameter named `capturedArguments` reaches the server")
    func toolCapturedArguments() async throws {
        let (proxy, client) = try await makeClient()
        defer { Task { await proxy.disconnect() } }
        #expect(try client.join(capturedArguments: ["x"], arguments: ["y"]) == "x,y")
    }

    @Test("parameters named like the generated locals' default names reach the server")
    func toolReservedLocalNames() async throws {
        let (proxy, client) = try await makeClient()
        defer { Task { await proxy.disconnect() } }
        #expect(try client.joinReserved(__mcpArguments: ["x"], __mcpCapturedArguments: "y") == "x,y")
        #expect(try client.joinReserved(__mcpArguments: ["x"]) == "x,-")
    }

    @Test("ProxyGenerator does not shadow a tool parameter named `arguments`")
    func proxyGeneratorDoesNotShadow() {
        let tool = MCPTool(
            name: "count",
            description: nil,
            inputSchema: .object(.init(
                properties: [
                    "arguments": .array(
                        items: .string(title: nil, description: nil),
                        title: nil,
                        description: nil
                    )
                ],
                required: ["arguments"]
            ))
        )
        let source = ProxyGenerator.generate(typeName: "CountProxy", tools: [tool]).description
        #expect(source.contains("__mcpArguments[\"arguments\"] = try MCPClientArgumentEncoder.encode(arguments)"))
        #expect(!source.contains("var arguments: JSONDictionary"))
    }

    @Test("ProxyGenerator picks a local that avoids a parameter named `__mcpArguments`")
    func proxyGeneratorAvoidsReservedLocalName() {
        let tool = MCPTool(
            name: "count",
            description: nil,
            inputSchema: .object(.init(
                properties: ["__mcpArguments": .string(title: nil, description: nil)],
                required: ["__mcpArguments"]
            ))
        )
        let source = ProxyGenerator.generate(typeName: "CountProxy", tools: [tool]).description
        let expected = "__mcpArguments_[\"__mcpArguments\"] = try MCPClientArgumentEncoder.encode(__mcpArguments)"
        #expect(source.contains(expected))
        #expect(source.contains("arguments: __mcpArguments_)"))
    }
}
