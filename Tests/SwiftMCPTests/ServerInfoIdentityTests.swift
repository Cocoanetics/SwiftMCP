import Foundation
import Testing
@testable import SwiftMCP

@MCPServer(name: "weather", title: "Weather Tools", websiteUrl: "https://example.com/weather")
final class RichIdentityServer: HasIcons {
    var icons: [Icon] { [Icon("https://example.com/icon.png", mimeType: "image/png")] }

    @MCPTool(description: "Ping")
    func ping() -> String { "pong" }
}

@MCPServer(name: "plain")
final class PlainIdentityServer {
    @MCPTool(description: "Ping")
    func ping() -> String { "pong" }
}

@Suite("serverInfo identity")
struct ServerInfoIdentityTests {

    // MARK: - Authoring (macro args / HasIcons -> protocol surface)

    @Test("@MCPServer(title:websiteUrl:) populates the protocol properties")
    func macroArgsPopulateProperties() {
        let server = RichIdentityServer()
        #expect(server.serverName == "weather")
        #expect(server.serverTitle == "Weather Tools")
        #expect(server.serverWebsiteUrl == URL(string: "https://example.com/weather"))
        #expect(server.icons.count == 1)
    }

    @Test("A plain server has no title / websiteUrl / icons")
    func plainServerDefaults() {
        let server = PlainIdentityServer()
        #expect(server.serverTitle == nil)
        #expect(server.serverWebsiteUrl == nil)
        #expect((server as? HasIcons) == nil)
    }

    // MARK: - Emission (version-gated)

    private func serverInfo<S: MCPServer>(
        version: String,
        make: @Sendable @escaping () -> S
    ) async -> JSONDictionary? {
        let request = JSONRPCMessage.request(
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": .string(version),
                "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("C"), "version": .string("1.0")])
            ]
        )
        let session = Session(id: UUID())
        let response = await session.work { _ in await make().handleMessage(request) }
        guard case .response(let data)? = response,
              let result = data.result,
              let info = result["serverInfo"]?.dictionaryValue else {
            return nil
        }
        return info
    }

    @Test("serverInfo includes title / icons / websiteUrl for 2025-06-18")
    func emitsRichIdentityForModern() async throws {
        let info = try #require(await serverInfo(version: "2025-06-18") { RichIdentityServer() })
        #expect(info["name"]?.stringValue == "weather")
        #expect(info["title"]?.stringValue == "Weather Tools")
        #expect(info["websiteUrl"]?.stringValue == "https://example.com/weather")
        #expect((info["icons"]?.value as? [[String: Any]])?.count == 1)
    }

    @Test("serverInfo omits title / icons / websiteUrl for 2025-03-26")
    func omitsRichIdentityForLegacy() async throws {
        let info = try #require(await serverInfo(version: "2025-03-26") { RichIdentityServer() })
        #expect(info["name"]?.stringValue == "weather")    // name always present
        #expect(info["title"] == nil)
        #expect(info["websiteUrl"] == nil)
        #expect(info["icons"] == nil)
    }

    @Test("serverInfo omits empty icons even when the version supports them")
    func omitsEmptyIcons() async throws {
        let info = try #require(await serverInfo(version: "2025-11-25") { PlainIdentityServer() })
        #expect(info["icons"] == nil)
        #expect(info["title"] == nil)
    }
}
