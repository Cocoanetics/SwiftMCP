import Foundation
import Testing
@testable import SwiftMCP

@MCPServer(name: "CacheTestServer", version: "1.0")
actor CacheTestServer: MCPCacheHintProviding {
    /// Returns the zebra fixture value.
    @MCPTool
    func zebra() -> String { "z" }

    /// Returns the alpha fixture value.
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

    @Test("Boolean-schema $ref targets and encoded pointers resolve")
    func booleanAndEncodedRefs() {
        let schema: JSONValue = .object([
            "$defs": .object(["No": .bool(false), "A/B": .object(["type": .string("string")])]),
            "properties": .object([
                "a": .object(["$ref": .string("#/$defs/No")]),
                "b": .object(["$ref": .string("#%2F$defs%2FA~1B")]),
                "c": .object(["$ref": .string("#/$defs/A%7E1B")])
            ])
        ])
        let props = schema.resolvingLocalRefs().dictionaryValue?["properties"]?.dictionaryValue
        #expect(props?["a"] == .bool(false))
        #expect(props?["b"]?.dictionaryValue?["type"] == .string("string"))
        #expect(props?["c"]?.dictionaryValue?["type"] == .string("string"))
    }

    @Test("Negative ttlMs is clamped to zero")
    func negativeTtl() {
        #expect(MCPCacheHint(ttlMs: -5, cacheScope: .public).ttlMs == 0)
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

/// Every cacheable method, per revision: hints in the modern era only, never on a
/// legacy session whatever revision it negotiated.
@Suite("Cacheable results by revision")
struct CacheableResultEraMatrixTests {

    static let requests: [(method: String, params: JSONDictionary)] = [
        ("tools/list", [:]),
        ("prompts/list", [:]),
        ("resources/list", [:]),
        ("resources/templates/list", [:]),
        ("resources/read", ["uri": .string("cfg://app")])
    ]

    private func hints(_ response: JSONRPCMessage?) -> (ttl: JSONValue?, scope: JSONValue?)? {
        guard case .response(let data)? = response, let result = data.result else { return nil }
        return (result["ttlMs"], result["cacheScope"])
    }

    @Test("Legacy sessions never carry cache hints", arguments: ["2025-03-26", "2025-06-18", "2025-11-25"])
    func legacyHasNoHints(version: String) async throws {
        let server = CacheTestServer()
        let session = Session(id: UUID())
        await session.setNegotiatedProtocolVersion(version)
        for (method, params) in Self.requests {
            let request = JSONRPCMessage.request(id: 1, method: method, params: .object(params))
            let response = await session.work { _ in await server.handleMessage(request) }
            let found = try #require(hints(response), "\(method) did not answer")
            #expect(found.ttl == nil, "\(method)")
            #expect(found.scope == nil, "\(method)")
        }
    }

    @Test("Modern requests carry cache hints on every cacheable method")
    func modernHasHints() async throws {
        let server = CacheTestServer()
        let meta: JSONDictionary = [
            MCPMetaKey.protocolVersion: .string(MCPProtocolVersion.modern),
            MCPMetaKey.clientInfo: .object(["name": .string("t"), "version": .string("1")]),
            MCPMetaKey.clientCapabilities: .object([:])
        ]
        for (method, params) in Self.requests {
            var withMeta = params
            withMeta["_meta"] = .object(meta)
            let request = JSONRPCMessage.request(id: 1, method: method, params: .object(withMeta))
            let response = await RequestContext(message: request).work { _ in await server.handleMessage(request) }
            let found = try #require(hints(response), "\(method) did not answer")
            #expect(found.ttl != nil, "\(method)")
            #expect(found.scope != nil, "\(method)")
        }
    }
}
