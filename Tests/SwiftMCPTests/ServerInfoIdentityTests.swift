import Foundation
import Testing
@testable import SwiftMCP

@MCPServer(
    name: "weather",
    title: "Weather Tools",
    websiteUrl: "https://example.com/weather",
    instructions: "Always confirm the location with the user before calling a tool."
)
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

/// Manages the widget inventory.
/// - Instructions: Always ask before deleting a widget.
@MCPServer(name: "widgets")
final class DocCInstructionsServer {
    @MCPTool(description: "Ping")
    func ping() -> String { "pong" }
}

@Suite("serverInfo identity")
struct ServerInfoIdentityTests {

    // MARK: - Authoring (macro args / HasIcons -> protocol surface)

    @Test("@MCPServer(title:websiteUrl:instructions:) populates the protocol properties")
    func macroArgsPopulateProperties() {
        let server = RichIdentityServer()
        #expect(server.serverName == "weather")
        #expect(server.serverTitle == "Weather Tools")
        #expect(server.serverWebsiteUrl == URL(string: "https://example.com/weather"))
        #expect(server.serverInstructions == "Always confirm the location with the user before calling a tool.")
        #expect(server.icons.count == 1)
    }

    @Test("A plain server has no title / websiteUrl / icons / instructions")
    func plainServerDefaults() {
        let server = PlainIdentityServer()
        #expect(server.serverTitle == nil)
        #expect(server.serverWebsiteUrl == nil)
        #expect(server.serverInstructions == nil)
        #expect((server as? HasIcons) == nil)
    }

    @Test("A `- Instructions:` DocC bullet populates serverInstructions when no explicit argument is given")
    func docCInstructionsFallback() {
        let server = DocCInstructionsServer()
        #expect(server.serverDescription == "Manages the widget inventory.")
        #expect(server.serverInstructions == "Always ask before deleting a widget.")
    }

    // MARK: - Emission (version-gated)

    private func serverInfo<S: MCPServer & SendableMetatype>(
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
        #expect((info["icons"]?.jsonObject as? [[String: Any]])?.count == 1)
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

    private func initializeResult<S: MCPServer & SendableMetatype>(
        make: @Sendable @escaping () -> S
    ) async -> JSONValue? {
        let request = JSONRPCMessage.request(
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": .string("2025-06-18"),
                "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("C"), "version": .string("1.0")])
            ]
        )
        let session = Session(id: UUID())
        let response = await session.work { _ in await make().handleMessage(request) }
        guard case .response(let data)? = response else { return nil }
        return data.result
    }

    @Test("initialize result carries instructions as a top-level field, not under serverInfo")
    func emitsInstructionsAtTopLevel() async throws {
        let result = try #require(await initializeResult { RichIdentityServer() })
        let expectedInstructions = "Always confirm the location with the user before calling a tool."
        #expect(result["instructions"]?.stringValue == expectedInstructions)
        #expect(result["serverInfo"]?.dictionaryValue?["instructions"] == nil)
    }

    @Test("initialize result omits instructions when unset")
    func omitsInstructionsWhenUnset() async throws {
        let result = try #require(await initializeResult { PlainIdentityServer() })
        #expect(result["instructions"] == nil)
    }

    // MARK: - Read path (decode -> Implementation, as MCPServerProxy does)

    @Test("Emitted serverInfo decodes back into InitializeResult (proxy read path)")
    func roundTripsToInitializeResult() async throws {
        let request = JSONRPCMessage.request(
            id: 1,
            method: "initialize",
            params: [
                "protocolVersion": .string("2025-06-18"),
                "capabilities": .object([:]),
                "clientInfo": .object(["name": .string("C"), "version": .string("1.0")])
            ]
        )
        let session = Session(id: UUID())
        let response = await session.work { _ in await RichIdentityServer().handleMessage(request) }
        guard case .response(let data)? = response, let result = data.result else {
            Issue.record("Expected an initialize response")
            return
        }

        // Exactly what MCPServerProxy does to capture the server's identity.
        let initResult = try result.decoded(InitializeResult.self)
        #expect(initResult.serverInfo.title == "Weather Tools")
        #expect(initResult.serverInfo.websiteUrl == URL(string: "https://example.com/weather"))
        #expect(initResult.serverInfo.icons?.count == 1)
        #expect(initResult.serverInfo.icons?.first?.src == URL(string: "https://example.com/icon.png"))
        #expect(initResult.instructions == "Always confirm the location with the user before calling a tool.")
    }
}
