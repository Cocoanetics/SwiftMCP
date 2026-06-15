import Foundation
import Testing
@testable import SwiftMCP

/// `outputSchema` (tools/list) and `structuredContent` (tools/call) are
/// structured-tool-output features introduced in `2025-06-18`. They must be
/// omitted for clients that negotiated an earlier revision.
@Suite("Structured tool output version gating")
struct StructuredToolOutputGatingTests {

    /// Routes a request through the server with `version` bound as the
    /// session-negotiated protocol version (the legacy resolution path).
    private func result(
        for request: JSONRPCMessage,
        negotiating version: String
    ) async -> JSONDictionary? {
        let session = Session(id: UUID())
        await session.setNegotiatedProtocolVersion(version)
        let response = await session.work { _ in
            await ComplexTypesServer().handleMessage(request)
        }
        guard case .response(let data)? = response else { return nil }
        return data.result
    }

    private func createContactTool(in tools: [[String: Any]]) throws -> [String: Any] {
        try #require(tools.first { $0["name"] as? String == "createContact" })
    }

    @Test("tools/list includes outputSchema for 2025-06-18 but omits it for 2025-03-26")
    func outputSchemaGated() async throws {
        let request = JSONRPCMessage.request(id: 1, method: "tools/list")

        let modern = try #require(await result(for: request, negotiating: "2025-06-18"))
        let modernTools = try #require(modern["tools"]?.value as? [[String: Any]])
        #expect(try createContactTool(in: modernTools)["outputSchema"] != nil)

        let legacy = try #require(await result(for: request, negotiating: "2025-03-26"))
        let legacyTools = try #require(legacy["tools"]?.value as? [[String: Any]])
        #expect(try createContactTool(in: legacyTools)["outputSchema"] == nil)
    }

    @Test("tools/call includes structuredContent for 2025-06-18 but omits it for 2025-03-26")
    func structuredContentGated() async throws {
        let request = JSONRPCMessage.request(
            id: 1,
            method: "tools/call",
            params: [
                "name": "createContact",
                "arguments": [
                    "name": "John Doe",
                    "email": "john@example.com",
                    "phone": "+1234567890",
                    "age": 30,
                    "isActive": true
                ]
            ]
        )

        let modern = try #require(await result(for: request, negotiating: "2025-06-18"))
        #expect(modern["structuredContent"] != nil)

        let legacy = try #require(await result(for: request, negotiating: "2025-03-26"))
        #expect(legacy["structuredContent"] == nil)
    }
}
