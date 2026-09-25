import Foundation
import Testing
@testable import SwiftMCP

/// Wraps a generated server the way a scoping layer does: it forwards the
/// resource surface and leaves out what its caller may not read.
struct ScopedResourceServer: MCPServer, MCPResourceProviding {
    let inner: ResourceTestServer
    let hidden: Set<String>

    var serverName: String { "ScopedResourceServer" }
    var serverVersion: String { "1.0" }

    var mcpResourceMetadata: [MCPResourceMetadata] {
        get async {
            await inner.mcpResourceMetadata.filter { $0.uriTemplates.isDisjoint(with: hidden) }
        }
    }

    var mcpResourceTemplates: [MCPResourceTemplate] {
        get async { await inner.mcpResourceTemplates }
    }

    func getResource(uri: URL) async throws -> [MCPResourceContent] {
        try await inner.getResource(uri: uri)
    }
}

@Suite("Static resources in resources/list", .tags(.unit))
struct StaticResourceListTests {
    @Test("A generated server lists its parameterless resources")
    func generatedServerListsStaticResources() async throws {
        let uris = await listedURIs(ResourceTestServer())
        #expect(uris.contains("config://app"))
        #expect(uris.contains("files://list"))
        // Resources with parameters belong to resources/templates/list.
        #expect(!uris.contains { $0.contains("{") })
    }

    @Test("A server that wraps a generated one lists the same static resources")
    func wrapperListsStaticResources() async throws {
        let inner = ResourceTestServer()
        let direct = await listedURIs(inner)
        let wrapped = await listedURIs(ScopedResourceServer(inner: inner, hidden: []))
        #expect(!direct.isEmpty)
        #expect(wrapped.sorted() == direct.sorted())
    }

    @Test("A wrapper's filtered metadata decides what is listed")
    func wrapperFilterDecidesWhatIsListed() async throws {
        let uris = await listedURIs(ScopedResourceServer(inner: ResourceTestServer(), hidden: ["config://app"]))
        #expect(!uris.contains("config://app"))
        #expect(uris.contains("files://list"))
    }

    private func listedURIs(_ server: some MCPServer) async -> [String] {
        let reply = await server.handleMessage(.request(id: 1, method: "resources/list"))
        guard case .response(let response)? = reply,
              let resources = response.result?["resources"]?.arrayValue else {
            Issue.record("resources/list did not answer with a list: \(String(describing: reply))")
            return []
        }
        return resources.compactMap { $0["uri"]?.stringValue }
    }
}
