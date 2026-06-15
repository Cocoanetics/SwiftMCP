import Foundation
import Testing
@testable import SwiftMCP

@MCPServer(name: "ResourceLinkServer")
final class ResourceLinkServer {
    @MCPTool(description: "Returns a resource link")
    func getLink() -> MCPResourceLink {
        MCPResourceLink(
            uri: URL(string: "file:///docs/readme.md")!,
            name: "README",
            description: "Project readme"
        )
    }

    @MCPTool(description: "Returns several resource links")
    func getLinks() -> [MCPResourceLink] {
        [
            MCPResourceLink(uri: URL(string: "file:///a.md")!, name: "A"),
            MCPResourceLink(uri: URL(string: "file:///b.md")!, name: "B")
        ]
    }
}

/// `resource_link` is a 2025-06-18 tool-result content type. For clients that
/// negotiated an earlier revision it is degraded to a plain `text` block that
/// still carries the link's name and URI.
@Suite("resource_link version gating")
struct ResourceLinkGatingTests {

    private func callTool(_ name: String, negotiating version: String) async -> [[String: Any]]? {
        let session = Session(id: UUID())
        await session.setNegotiatedProtocolVersion(version)
        let request = JSONRPCMessage.request(
            id: 1,
            method: "tools/call",
            params: ["name": .string(name), "arguments": [:]]
        )
        let response = await session.work { _ in
            await ResourceLinkServer().handleMessage(request)
        }
        guard case .response(let data)? = response,
              let result = data.result,
              let content = result["content"]?.value as? [[String: Any]] else {
            return nil
        }
        return content
    }

    @Test("resource_link is preserved for 2025-06-18")
    func preservedForModern() async throws {
        let content = try #require(await callTool("getLink", negotiating: "2025-06-18"))
        let first = try #require(content.first)
        #expect(first["type"] as? String == "resource_link")
        #expect(first["uri"] as? String == "file:///docs/readme.md")
    }

    @Test("resource_link degrades to a text block carrying name and URI for 2025-03-26")
    func degradedForLegacy() async throws {
        let content = try #require(await callTool("getLink", negotiating: "2025-03-26"))
        let first = try #require(content.first)
        #expect(first["type"] as? String == "text")
        #expect(first["uri"] == nil)
        let text = try #require(first["text"] as? String)
        #expect(text.contains("README"))
        #expect(text.contains("file:///docs/readme.md"))
        #expect(text.contains("Project readme"))
    }

    @Test("each resource_link in an array degrades for 2025-03-26")
    func arrayDegradedForLegacy() async throws {
        let content = try #require(await callTool("getLinks", negotiating: "2025-03-26"))
        #expect(content.count == 2)
        #expect(content.allSatisfy { $0["type"] as? String == "text" })

        let modern = try #require(await callTool("getLinks", negotiating: "2025-06-18"))
        #expect(modern.allSatisfy { $0["type"] as? String == "resource_link" })
    }
}
