#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// A fixture whose tool declares a header-mirrored parameter.
@MCPServer(name: "HeaderParamServer", version: "1.0")
actor HeaderParamTestServer {
    /// Echoes a greeting.
    /// - Parameter user: The user to greet.
    /// - Parameter excited: Whether to shout.
    /// - Returns: The greeting.
    @MCPTool(description: "Greets a user", headerParameters: ["user"])
    func greet(user: String, excited: Bool = false) -> String {
        excited ? "HELLO \(user)!" : "Hello \(user)"
    }
}

@Suite("Origin allowlist & x-mcp-header (Phase 2d)")
struct OriginAndXMcpHeaderTests {

    private func jsonHeaders() -> HTTPFields {
        [.accept: "application/json, text/event-stream", .contentType: "application/json"]
    }

    private func drain(_ exchange: InMemoryHTTPServerAdapter.Exchange) async -> String {
        guard case .sse(let stream) = exchange.body else { return "" }
        var data = Data()
        for await chunk in stream { data.append(chunk) }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    // MARK: - Origin allowlist

    @Test("Origin allowlist unset → any Origin passes (regression)")
    func originUnsetPasses() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        var headers = jsonHeaders()
        headers[.origin] = "https://evil.example"
        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
        #expect(exchange.status == .ok)
    }

    @Test("Disallowed Origin → 403 on POST /mcp, GET /sse, and OPTIONS preflight")
    func disallowedOriginIs403() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        transport.allowedOrigins = ["https://app.example.com"]
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        var headers = jsonHeaders()
        headers[.origin] = "https://evil.example"

        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let post = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
        #expect(post.status == .forbidden)

        let sse = await adapter.send(method: .get, path: "/sse", headerFields: [.origin: "https://evil.example"])
        #expect(sse.status == .forbidden)

        let preflight = await adapter.send(
            method: .options, path: "/mcp", headerFields: [.origin: "https://evil.example"]
        )
        #expect(preflight.status == .forbidden)
    }

    @Test("Allowed Origin and no-Origin requests pass the allowlist")
    func allowedAndAbsentOriginPass() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        transport.allowedOrigins = ["https://app.example.com"]
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())

        var allowed = jsonHeaders()
        allowed[.origin] = "https://app.example.com"
        let allowedExchange = await adapter.send(method: .post, path: "/mcp", headerFields: allowed, body: body)
        #expect(allowedExchange.status == .ok)

        // No Origin header (curl / native clients) always passes.
        let bare = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: body)
        #expect(bare.status == .ok)
    }

    // MARK: - x-mcp-header metadata + emission

    @Test("headerParameters flags the parameter in the tool metadata")
    func metadataCarriesHeaderFlag() async throws {
        let server = HeaderParamTestServer()
        let metadata = await server.mcpToolMetadata
        let greet = try #require(metadata.first { $0.name == "greet" })
        #expect(greet.parameters.first { $0.name == "user" }?.isMirroredToHeader == true)
        #expect(greet.parameters.first { $0.name == "excited" }?.isMirroredToHeader == false)
    }

    @Test("Modern tools/list carries x-mcp-header; legacy does not")
    func emissionIsProfileGated() async throws {
        let transport = HTTPSSETransport(server: HeaderParamTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // Modern request: annotation present.
        let modern = JSONRPCMessage.request(
            id: 1, method: "tools/list",
            params: .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])])
        )
        var modernHeaders = jsonHeaders()
        modernHeaders[.mcpProtocolVersion] = "2026-07-28"
        modernHeaders[.mcpMethod] = "tools/list"
        let modernExchange = await adapter.send(
            method: .post, path: "/mcp", headerFields: modernHeaders,
            body: try HTTPTransportTestHelpers.encode(modern)
        )
        let modernText = await drain(modernExchange)
        #expect(modernText.contains("x-mcp-header"))

        // Legacy session: annotation absent.
        let initBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let initExchange = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: initBody)
        let sessionID = try #require(initExchange.headerFields[.mcpSessionID])
        _ = await drain(initExchange)

        var legacyHeaders = jsonHeaders()
        legacyHeaders[.mcpSessionID] = sessionID
        let legacy = JSONRPCMessage.request(id: 2, method: "tools/list", params: nil)
        let legacyExchange = await adapter.send(
            method: .post, path: "/mcp", headerFields: legacyHeaders,
            body: try HTTPTransportTestHelpers.encode(legacy)
        )
        let legacyText = await drain(legacyExchange)
        #expect(!legacyText.contains("x-mcp-header"))
    }

    // MARK: - Mcp-Param-* validation

    private func toolsCall(arguments: JSONDictionary) -> JSONRPCMessage {
        .request(id: 1, method: "tools/call", params: .object([
            "name": .string("greet"),
            "arguments": .object(arguments),
            "_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])
        ]))
    }

    private func callHeaders(_ extra: [HTTPField.Name: String] = [:]) -> HTTPFields {
        var headers = jsonHeaders()
        headers[.mcpProtocolVersion] = "2026-07-28"
        headers[.mcpMethod] = "tools/call"
        headers[.mcpName] = "greet"
        for (name, value) in extra { headers[name] = value }
        return headers
    }

    private func send(
        _ headers: HTTPFields, _ message: JSONRPCMessage,
        server: HeaderParamTestServer = HeaderParamTestServer()
    ) async throws -> InMemoryHTTPServerAdapter.Exchange {
        let transport = HTTPSSETransport(server: server)
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let body = try HTTPTransportTestHelpers.encode(message)
        return await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
    }

    private func isHeaderMismatch(_ exchange: InMemoryHTTPServerAdapter.Exchange) -> Bool {
        guard exchange.status == .badRequest, case .buffered(let data?) = exchange.body,
              let text = String(bytes: data, encoding: .utf8) else {
            return false
        }
        return text.contains("-32001") && text.contains("HeaderMismatch")
    }

    @Test("Matching Mcp-Param header → served; mismatch / unknown / malformed sentinel → -32001")
    func paramHeaderValidation() async throws {
        let mcpParamUser = HTTPField.Name("Mcp-Param-user")!

        let matching = try await send(
            callHeaders([mcpParamUser: "Oliver"]), toolsCall(arguments: ["user": .string("Oliver")])
        )
        #expect(matching.status == .ok)

        let mismatched = try await send(
            callHeaders([mcpParamUser: "Mallory"]), toolsCall(arguments: ["user": .string("Oliver")])
        )
        #expect(isHeaderMismatch(mismatched))

        let unknownParam = HTTPField.Name("Mcp-Param-nonexistent")!
        let unknown = try await send(
            callHeaders([unknownParam: "x"]), toolsCall(arguments: ["user": .string("Oliver")])
        )
        #expect(isHeaderMismatch(unknown))

        let malformed = try await send(
            callHeaders([mcpParamUser: "=?base64?!!!not-base64!!!?="]),
            toolsCall(arguments: ["user": .string("Oliver")])
        )
        #expect(isHeaderMismatch(malformed))
    }

    @Test("Base64 sentinel decodes non-ASCII values; non-string args compare as JSON text")
    func paramHeaderEncodings() async throws {
        let mcpParamUser = HTTPField.Name("Mcp-Param-user")!
        let umlautName = "Jörg"
        let sentinel = "=?base64?\(Data(umlautName.utf8).base64EncodedString())?="
        let nonASCII = try await send(
            callHeaders([mcpParamUser: sentinel]), toolsCall(arguments: ["user": .string(umlautName)])
        )
        #expect(nonASCII.status == .ok)

        // A non-string argument compares against its JSON text.
        let mcpParamExcited = HTTPField.Name("Mcp-Param-excited")!
        let boolArg = try await send(
            callHeaders([mcpParamUser: "Oliver", mcpParamExcited: "true"]),
            toolsCall(arguments: ["user": .string("Oliver"), "excited": .bool(true)])
        )
        #expect(boolArg.status == .ok)
    }

    @Test("No Mcp-Param headers → served (presence is not required)")
    func paramHeadersOptional() async throws {
        let exchange = try await send(callHeaders(), toolsCall(arguments: ["user": .string("Oliver")]))
        #expect(exchange.status == .ok)
    }

    // MARK: - Review-fix regressions

    @Test("Origin comparison is case-insensitive (RFC 6454)")
    func originCaseInsensitive() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        transport.allowedOrigins = ["https://app.example.com"]
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        var headers = jsonHeaders()
        headers[.origin] = "https://APP.Example.COM"   // re-cased by an intermediary
        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
        #expect(exchange.status == .ok)
    }

    @Test("Case-ambiguous argument names reject deterministically")
    func caseAmbiguousParamRejects() async throws {
        // Two arguments differing only by case: the header can match neither
        // nondeterministically — ambiguity is a mismatch. An exact-name match
        // still wins outright.
        let mcpParamUser = HTTPField.Name("Mcp-Param-USER")!
        let ambiguous = try await send(
            callHeaders([mcpParamUser: "a"]),
            toolsCall(arguments: ["user": .string("a"), "User": .string("b")])
        )
        #expect(isHeaderMismatch(ambiguous))

        let exact = HTTPField.Name("Mcp-Param-user")!
        let exactMatch = try await send(
            callHeaders([exact: "a"]),
            toolsCall(arguments: ["user": .string("a"), "User": .string("b")])
        )
        #expect(exactMatch.status == .ok)
    }

    @Test("Object-valued arguments compare via sorted-keys JSON text")
    func objectParamComparesDeterministically() async throws {
        let mcpParamUser = HTTPField.Name("Mcp-Param-user")!
        let mcpParamConfig = HTTPField.Name("Mcp-Param-config")!
        // Sorted-keys canonical text of the object, regardless of body key order.
        let exchange = try await send(
            callHeaders([mcpParamUser: "Oliver", mcpParamConfig: #"{"alpha":1,"beta":2}"#]),
            toolsCall(arguments: [
                "user": .string("Oliver"),
                "config": .object(["beta": .integer(2), "alpha": .integer(1)])
            ])
        )
        #expect(exchange.status == .ok)
    }
}
#endif
