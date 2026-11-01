import Foundation
import Testing
@testable import SwiftMCP

@MCPServer(name: "CacheTestServer", version: "1.0")
actor CacheTestServer: MCPCacheHintProviding {
    @MCPTool
    func zebra() -> String { "z" }

    @MCPTool
    func alpha() -> String { "a" }

    @MCPResource("cfg://app")
    func config() -> String { "cfg" }

    func cacheHint(for method: MCPCacheableMethod) async -> MCPCacheHint {
        method == .toolsList ? MCPCacheHint(ttlMs: 60_000, cacheScope: .public) : .default
    }
}

@Suite("Cacheable results, ordering, schema passthrough")
struct CacheableResultTests {

    private func context(version: String?) -> RequestContext {
        var params: JSONDictionary = [:]
        if let version {
            params["_meta"] = .object([MCPMetaKey.protocolVersion: .string(version)])
        }
        return RequestContext(message: .request(id: 1, method: "tools/list", params: .object(params)))
    }

    private func result(_ message: JSONRPCMessage) throws -> JSONValue {
        guard case .response(let response) = message, let result = response.result else {
            throw TestError("Expected response")
        }
        return result
    }

    @Test("Modern tools/list includes ttlMs and cacheScope")
    func modernToolsListIncludesTtlMsAndCacheScope() async throws {
        let server = CacheTestServer()
        let message = await context(version: "2026-07-28").work { _ in
            await server.createToolsListResponse(id: 1)
        }
        let result = try result(message)
        #expect(result["ttlMs"] == .integer(60_000))
        #expect(result["cacheScope"] == .string("public"))
    }

    @Test("Modern resources/list uses the default hint; legacy output has no hints")
    func defaultAndLegacy() async throws {
        let server = CacheTestServer()
        let modern = try result(await context(version: "2026-07-28").work { _ in
            await server.createResourcesListResponse(id: 1)
        })
        #expect(modern["ttlMs"] == .integer(0))
        #expect(modern["cacheScope"] == .string("private"))

        for ctx in [context(version: nil), context(version: "2025-11-25")] {
            let legacy = try result(await ctx.work { _ in await server.createToolsListResponse(id: 1) })
            #expect(legacy["ttlMs"] == nil)
            #expect(legacy["cacheScope"] == nil)
        }
    }

    @Test("tools/list is sorted by name")
    func toolsSorted() async throws {
        let server = CacheTestServer()
        let result = try result(await server.createToolsListResponse(id: 1))
        let names = result["tools"]?.arrayValue?.compactMap { $0.dictionaryValue?["name"]?.stringValue }
        #expect(names == ["alpha", "zebra"])
    }

    @Test("Unknown schema keywords round-trip and $ref resolves")
    func schemaPassthrough() throws {
        let json = Data("""
        {"name":"t","inputSchema":{"type":"object","$defs":{"N":{"type":"integer","minimum":3}},
        "properties":{"n":{"$ref":"#/$defs/N"}},"unevaluatedProperties":false,"x-custom":[1,2]},
        "outputSchema":{"oneOf":[{"type":"string"},{"type":"array"}]}}
        """.utf8)
        let tool = try JSONDecoder().decode(MCPTool.self, from: json)
        let encoded = try JSONEncoder().encode(tool)
        let original = try JSONDecoder().decode(JSONValue.self, from: json)
        #expect(try JSONDecoder().decode(JSONValue.self, from: encoded) == original)

        let resolved = try #require(tool.rawInputSchema).resolvingLocalRefs()
        let prop = resolved.dictionaryValue?["properties"]?.dictionaryValue?["n"]?.dictionaryValue
        #expect(prop?["minimum"] == .integer(3))
        #expect(prop?["$ref"] == nil)
    }

    @Test("Cyclic $ref is left unresolved")
    func cyclicRef() throws {
        let schema: JSONValue = .object([
            "$defs": .object(["A": .object(["$ref": .string("#/$defs/A")])]),
            "$ref": .string("#/$defs/A")
        ])
        _ = schema.resolvingLocalRefs()
    }

    @Test("structuredContent accepts any JSON value")
    func nonObjectStructuredContent() {
        let result = MCPToolCallResult(content: [], structuredContent: .array([.integer(1)]))
        #expect(result.structuredContent == .array([.integer(1)]))
    }

    @Test("Resource not-found code follows the profile")
    func notFoundCode() async throws {
        for (version, code) in [("2026-07-28", -32602), ("2025-11-25", -32001)] {
            let message = await context(version: version).work { _ in
                await CacheTestServer.resourceNotFoundResponse(id: 1, uri: "x://y")
            }
            guard case .errorResponse(let error) = message else { throw TestError("Expected error") }
            #expect(error.error.code == code)
        }
    }
}
