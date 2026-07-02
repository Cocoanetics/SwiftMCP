import Testing
import Foundation
@testable import SwiftMCP

@Suite("DiscoverResult & capability extensions (Codable)")
struct DiscoverModelTests {

    @Test("ServerCapabilities.extensions is omitted when nil and round-trips when set")
    func serverExtensions() throws {
        var caps = ServerCapabilities()
        #expect(caps.extensions == nil)
        let emptyJSON = String(data: try JSONEncoder().encode(caps), encoding: .utf8) ?? ""
        #expect(!emptyJSON.contains("extensions"))   // seam not advertised when empty

        caps.extensions = ["io.modelcontextprotocol/tasks": .object(["version": .string("1")])]
        let decoded = try JSONDecoder().decode(ServerCapabilities.self, from: try JSONEncoder().encode(caps))
        #expect(decoded.extensions?["io.modelcontextprotocol/tasks"] != nil)
    }

    @Test("ClientCapabilities.extensions round-trips")
    func clientExtensions() throws {
        var caps = ClientCapabilities()
        #expect(caps.extensions == nil)
        caps.extensions = ["io.modelcontextprotocol/ui": .object([:])]
        let decoded = try JSONDecoder().decode(ClientCapabilities.self, from: try JSONEncoder().encode(caps))
        #expect(decoded.extensions?["io.modelcontextprotocol/ui"] != nil)
    }

    @Test("DiscoverResult round-trips; optional cache hints omitted when nil")
    func discoverResultCodable() throws {
        let result = DiscoverResult(
            supportedVersions: ["2025-11-25", "2025-06-18"],
            capabilities: ServerCapabilities(),
            serverInfo: Implementation(name: "X", version: "1.0")
        )
        let json = String(data: try JSONEncoder().encode(result), encoding: .utf8) ?? ""
        #expect(!json.contains("ttlMs"))
        #expect(!json.contains("cacheScope"))
        #expect(!json.contains("instructions"))

        let decoded = try JSONDecoder().decode(DiscoverResult.self, from: try JSONEncoder().encode(result))
        #expect(decoded.resultType == "complete")
        #expect(decoded.supportedVersions == ["2025-11-25", "2025-06-18"])
        #expect(decoded.serverInfo.name == "X")
    }

    @Test("supportedDescending orders the negotiable revisions newest-first")
    func supportedDescendingOrder() {
        #expect(MCPProtocolVersion.supportedDescending == ["2025-11-25", "2025-06-18", "2025-03-26"])
    }

    @Test("isModern / isServable split advertised from processable versions")
    func modernAndServable() {
        // 2026-07-28 is a known modern revision, servable, but NOT advertised.
        #expect(MCPProtocolVersion.isModern("2026-07-28"))
        #expect(MCPProtocolVersion.isServable("2026-07-28"))
        #expect(!MCPProtocolVersion.supported.contains("2026-07-28"))

        // Negotiable legacy revisions: servable, not modern.
        #expect(!MCPProtocolVersion.isModern("2025-11-25"))
        #expect(MCPProtocolVersion.isServable("2025-11-25"))

        // A known-but-non-negotiable legacy revision (2024-11-05) is neither.
        #expect(!MCPProtocolVersion.isModern("2024-11-05"))
        #expect(!MCPProtocolVersion.isServable("2024-11-05"))

        // An unknown version is neither modern nor servable.
        #expect(!MCPProtocolVersion.isModern("2099-01-01"))
        #expect(!MCPProtocolVersion.isServable("2099-01-01"))
    }
}
