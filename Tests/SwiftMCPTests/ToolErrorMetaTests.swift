import Foundation
import Testing
@testable import SwiftMCP

/// A tool error with details for the client.
struct DetailedRefusal: MCPToolErrorMetaProviding, LocalizedError {
    var errorDescription: String? { "The agent refused mode \"plan\"" }
    var toolErrorMeta: JSONDictionary {
        ["com.example/error": .object(["code": .integer(-32602), "data": .object(["mode": .string("plan")])])]
    }
}

/// A tool error whose details are empty.
struct EmptyDetails: MCPToolErrorMetaProviding, LocalizedError {
    var errorDescription: String? { "Nothing to add" }
    var toolErrorMeta: JSONDictionary { [:] }
}

/// A plain tool error.
struct PlainFailure: LocalizedError {
    var errorDescription: String? { "Plain failure" }
}

@MCPServer(name: "Tool Error Fixture")
final class ToolErrorFixtureServer: Sendable {
    /// Refuses, with details.
    @MCPTool
    func refuse() throws -> String { throw DetailedRefusal() }

    /// Fails, with details that are empty.
    @MCPTool
    func shrug() throws -> String { throw EmptyDetails() }

    /// Fails plainly.
    @MCPTool
    func fail() throws -> String { throw PlainFailure() }
}

@Suite("Tool errors with _meta", .tags(.mockClient, .unit))
struct ToolErrorMetaTests {
    /// The tool's result for `tools/call` of `name`, as the server answers it.
    private func result(of name: String) async throws -> JSONValue {
        let client = MockClient(server: ToolErrorFixtureServer())
        let request = JSONRPCMessage.request(id: 1, method: "tools/call", params: ["name": .string(name)])
        let message = try #require(await client.send(request))
        guard case .response(let response) = message else {
            throw TestError("Expected response case")
        }
        return try #require(response.result)
    }

    @Test("an error's details go out as _meta on the isError result, beside its text")
    func detailsRideOnTheErrorResult() async throws {
        let result = try await result(of: "refuse")
        #expect(result["isError"] == .bool(true))
        #expect(result["content"] == .array([
            .object(["type": .string("text"), "text": .string("The agent refused mode \"plan\"")])
        ]))
        #expect(result["_meta"] == .object(DetailedRefusal().toolErrorMeta))
    }

    @Test("a plain error, or empty details, sends no _meta")
    func noDetailsSendNoMeta() async throws {
        for name in ["fail", "shrug"] {
            let result = try await result(of: name)
            #expect(result["isError"] == .bool(true), "\(name)")
            #expect(result["_meta"] == nil, "\(name)")
        }
    }

    @Test("a client throws the details as toolErrorWithMeta")
    func theClientThrowsTheDetails() async throws {
        let proxy = MCPServerProxy(config: .stdioHandles(server: ToolErrorFixtureServer()))
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        do {
            _ = try await proxy.callTool("refuse")
            Issue.record("The call should have failed")
        } catch MCPServerProxyError.toolErrorWithMeta(let message, let meta) {
            #expect(message == "The agent refused mode \"plan\"")
            #expect(meta == DetailedRefusal().toolErrorMeta)
            #expect(MCPServerProxyError.toolErrorWithMeta(message, meta: meta).localizedDescription
                == "Tool call failed: The agent refused mode \"plan\"")
        }
    }

    @Test("a failed call without _meta is toolError, as before")
    func withoutMetaItIsToolError() async throws {
        let proxy = MCPServerProxy(config: .stdioHandles(server: ToolErrorFixtureServer()))
        try await proxy.connect()
        defer { Task { await proxy.disconnect() } }

        for (name, text) in [("fail", "Plain failure"), ("shrug", "Nothing to add")] {
            do {
                _ = try await proxy.callTool(name)
                Issue.record("The call to \(name) should have failed")
            } catch MCPServerProxyError.toolError(let message) {
                #expect(message == text)
            }
        }
    }
}
