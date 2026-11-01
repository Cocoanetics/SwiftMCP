#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// Era matrix for the Streamable HTTP endpoint: modern POSTs are sessionless,
/// `GET`/`DELETE /mcp` are `405` for modern requests and modern-only servers, and
/// a dual-era server keeps them for legacy clients.
@Suite("Streamable HTTP era matrix")
struct StreamableHTTPEraMatrixTests {

    private func jsonHeaders() -> HTTPFields {
        [.accept: "application/json, text/event-stream", .contentType: "application/json"]
    }

    private func modernToolsList() throws -> (HTTPFields, Data) {
        let message = JSONRPCMessage.request(
            id: 1, method: "tools/list",
            params: .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])])
        )
        var headers = jsonHeaders()
        headers[.mcpProtocolVersion] = "2026-07-28"
        headers[.mcpMethod] = "tools/list"
        return (headers, try HTTPTransportTestHelpers.encode(message))
    }

    struct VerbCase: Sendable, CustomTestStringConvertible {
        let name: String
        let method: HTTPRequest.Method
        let modernHeader: Bool
        let legacyEra: Bool
        let expects405: Bool
        var testDescription: String { name }
    }

    static let verbCases: [VerbCase] = [
        .init(name: "modern GET, dual-era", method: .get, modernHeader: true, legacyEra: true, expects405: true),
        .init(name: "modern DELETE, dual-era", method: .delete, modernHeader: true, legacyEra: true, expects405: true),
        .init(name: "legacy GET, modern-only", method: .get, modernHeader: false, legacyEra: false, expects405: true),
        .init(
            name: "legacy DELETE, modern-only", method: .delete, modernHeader: false, legacyEra: false, expects405: true
        ),
        .init(name: "legacy GET, dual-era", method: .get, modernHeader: false, legacyEra: true, expects405: false),
        .init(name: "legacy DELETE, dual-era", method: .delete, modernHeader: false, legacyEra: true, expects405: false)
    ]

    @Test("GET/DELETE /mcp: 405 by era", arguments: verbCases)
    func verbsByEra(_ testCase: VerbCase) async throws {
        let transport = HTTPSSETransport(server: Calculator())
        transport.servesLegacyEra = testCase.legacyEra
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        var headers: HTTPFields = [:]
        if testCase.modernHeader {
            headers[.mcpProtocolVersion] = "2026-07-28"
        }
        let exchange = await adapter.send(method: testCase.method, path: "/mcp", headerFields: headers)

        if testCase.expects405 {
            #expect(exchange.status == .methodNotAllowed)
        } else {
            #expect(exchange.status != .methodNotAllowed)
        }
    }

    @Test("Modern POST is sessionless; legacy initialize mints a session")
    func postSessionByEra() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let (modernHeaders, modernBody) = try modernToolsList()
        let modern = await adapter.send(method: .post, path: "/mcp", headerFields: modernHeaders, body: modernBody)
        #expect(modern.status == .ok)
        #expect(modern.headerFields[.mcpSessionID] == nil)
        #expect(modern.headerFields[.xAccelBuffering] == "no")

        let initBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let legacy = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: initBody)
        #expect(legacy.status == .ok)
        #expect(legacy.headerFields[.mcpSessionID] != nil)
    }

    @Test("A modern POST ignores an inbound Mcp-Session-Id and echoes none")
    func modernPostIgnoresSessionHeader() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        var (headers, body) = try modernToolsList()
        headers[.mcpSessionID] = UUID().uuidString
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
        #expect(exchange.status == .ok)
        #expect(exchange.headerFields[.mcpSessionID] == nil)
    }

    @Test("A newer MCP-Protocol-Version header on legacy initialize is tolerated")
    func newerVersionHeaderOnLegacyInitialize() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        var headers = jsonHeaders()
        headers[.mcpProtocolVersion] = "2099-01-01"
        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
        #expect(exchange.status == .ok)
        #expect(exchange.headerFields[.mcpSessionID] != nil)
    }

    @Test("An unknown newer version header on a non-initialize request is still rejected")
    func newerVersionHeaderOnOtherRequestRejected() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        var headers = jsonHeaders()
        headers[.mcpProtocolVersion] = "2099-01-01"
        let body = try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(id: 1, method: "tools/list", params: nil))
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
        #expect(exchange.status == .badRequest)
    }
}
#endif
