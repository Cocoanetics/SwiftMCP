#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// Exercises the modern (`2026-07-28`) required-header validation over the
/// socket-free ``InMemoryHTTPServerAdapter``: `MCP-Protocol-Version` / `Mcp-Method`
/// / `Mcp-Name` must match the body, else `400` + `-32001`.
@Suite("Modern required-header validation (-32001)")
struct ModernHeaderValidationTests {

    private func modernBody(method: String, extra: [String: JSONValue] = [:]) throws -> Data {
        var params: JSONDictionary = [
            "_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])
        ]
        for (key, value) in extra { params[key] = value }
        return try HTTPTransportTestHelpers.encode(
            JSONRPCMessage.request(id: 1, method: method, params: .object(params))
        )
    }

    private func send(
        _ headers: HTTPFields, method: String, extra: [String: JSONValue] = [:]
    ) async throws -> InMemoryHTTPServerAdapter.Exchange {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let body = try modernBody(method: method, extra: extra)
        return await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
    }

    private func isHeaderMismatch(_ exchange: InMemoryHTTPServerAdapter.Exchange) -> Bool {
        guard exchange.status == .badRequest, case .buffered(let data?) = exchange.body,
              let text = String(bytes: data, encoding: .utf8) else {
            return false
        }
        return text.contains("-32001") && text.contains("HeaderMismatch")
    }

    private func baseHeaders(_ extra: [HTTPField.Name: String]) -> HTTPFields {
        var headers: HTTPFields = [
            .accept: "application/json, text/event-stream", .contentType: "application/json"
        ]
        for (name, value) in extra { headers[name] = value }
        return headers
    }

    @Test("All required headers correct → served, not -32001")
    func allHeadersCorrect() async throws {
        let headers = baseHeaders([.mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/list"])
        let exchange = try await send(headers, method: "tools/list")
        #expect(exchange.status == .ok)
        #expect(!isHeaderMismatch(exchange))
    }

    @Test("Missing MCP-Protocol-Version → -32001")
    func missingProtocolVersion() async throws {
        // Classified modern by the body _meta even without the header, so validation
        // runs and rejects the absent header.
        let headers = baseHeaders([.mcpMethod: "tools/list"])
        #expect(isHeaderMismatch(try await send(headers, method: "tools/list")))
    }

    @Test("Mismatched Mcp-Method → -32001")
    func mismatchedMethod() async throws {
        let headers = baseHeaders([.mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/call"])
        #expect(isHeaderMismatch(try await send(headers, method: "tools/list")))
    }

    @Test("Missing Mcp-Name for tools/call → -32001")
    func missingNameForToolsCall() async throws {
        let headers = baseHeaders([.mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/call"])
        let exchange = try await send(headers, method: "tools/call", extra: ["name": .string("add")])
        #expect(isHeaderMismatch(exchange))
    }

    @Test("Matched Mcp-Name for tools/call → passes validation")
    func matchedNameForToolsCall() async throws {
        let headers = baseHeaders([
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/call", .mcpName: "add"
        ])
        let exchange = try await send(headers, method: "tools/call", extra: ["name": .string("add")])
        #expect(!isHeaderMismatch(exchange))   // header validation passed; tool result is separate
    }

    @Test("Mismatched MCP-Protocol-Version value → -32001")
    func mismatchedProtocolVersionValue() async throws {
        let headers = baseHeaders([.mcpProtocolVersion: "2025-11-25", .mcpMethod: "tools/list"])
        #expect(isHeaderMismatch(try await send(headers, method: "tools/list")))
    }

    @Test("Mismatched Mcp-Name value for tools/call → -32001")
    func mismatchedNameForToolsCall() async throws {
        let headers = baseHeaders([
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/call", .mcpName: "multiply"
        ])
        let exchange = try await send(headers, method: "tools/call", extra: ["name": .string("add")])
        #expect(isHeaderMismatch(exchange))
    }

    @Test("Orphaned Mcp-Name header (no params.name in body) → -32001")
    func orphanedNameHeader() async throws {
        // Header present, body field absent: a one-sided value is a mismatch, not a
        // skipped check.
        let headers = baseHeaders([
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/call", .mcpName: "add"
        ])
        let exchange = try await send(headers, method: "tools/call")
        #expect(isHeaderMismatch(exchange))
    }

    @Test("Non-string params.name is a mismatch, with or without an Mcp-Name header")
    func nonStringNameIsMalformed() async throws {
        // A present-but-non-string body field can never be mirrored by a header —
        // it must not degrade to "absent" and slip past a headerless request.
        let headerless = baseHeaders([.mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/call"])
        let noHeader = try await send(headerless, method: "tools/call", extra: ["name": .integer(42)])
        #expect(isHeaderMismatch(noHeader))

        let withHeader = baseHeaders([
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/call", .mcpName: "42"
        ])
        let mirrored = try await send(withHeader, method: "tools/call", extra: ["name": .integer(42)])
        #expect(isHeaderMismatch(mirrored))
    }

    @Test("A non-string _meta.protocolVersion classifies the request as legacy")
    func nonStringMetaVersionIsLegacy() {
        let message = JSONRPCMessage.request(
            id: 1, method: "tools/list",
            params: .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .integer(2026)])])
        )
        #expect(!SessionInitializationGate.batchIsModern([message]))
    }

    @Test("prompts/get: missing Mcp-Name → -32001; matched → passes")
    func promptsGetNameValidation() async throws {
        let missing = baseHeaders([.mcpProtocolVersion: "2026-07-28", .mcpMethod: "prompts/get"])
        let rejected = try await send(missing, method: "prompts/get", extra: ["name": .string("greet")])
        #expect(isHeaderMismatch(rejected))

        let matched = baseHeaders([
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: "prompts/get", .mcpName: "greet"
        ])
        let accepted = try await send(matched, method: "prompts/get", extra: ["name": .string("greet")])
        #expect(!isHeaderMismatch(accepted))
    }

    @Test("resources/read: Mcp-Name mirrors the uri; modern not-found is -32602")
    func resourcesReadNameValidation() async throws {
        let uri = "file:///nope.txt"
        let missing = baseHeaders([.mcpProtocolVersion: "2026-07-28", .mcpMethod: "resources/read"])
        let rejected = try await send(missing, method: "resources/read", extra: ["uri": .string(uri)])
        #expect(isHeaderMismatch(rejected))

        let matched = baseHeaders([
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: "resources/read", .mcpName: uri
        ])
        let accepted = try await send(matched, method: "resources/read", extra: ["uri": .string(uri)])
        #expect(!isHeaderMismatch(accepted))
        // Header validation passed; the unknown resource then fails with the
        // *modern* not-found code (-32602), not legacy -32001.
        guard case .sse(let stream) = accepted.body else {
            Issue.record("expected an SSE reply for the request-bearing POST")
            return
        }
        var data = Data()
        for await chunk in stream { data.append(chunk) }
        let text = String(bytes: data, encoding: .utf8) ?? ""
        #expect(text.contains("-32602"))
        #expect(!text.contains("-32001"))
    }

    @Test("Mcp-Name is not required for methods that don't use it")
    func nameNotRequiredForToolsList() async throws {
        let headers = baseHeaders([.mcpProtocolVersion: "2026-07-28", .mcpMethod: "tools/list"])
        let exchange = try await send(headers, method: "tools/list")
        #expect(exchange.status == .ok)
        #expect(!isHeaderMismatch(exchange))
    }

    @Test("Legacy POST is unaffected by the modern header rules")
    func legacyUnaffected() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        // Legacy initialize: no modern _meta, no modern headers → not validated.
        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let headers: HTTPFields = [.accept: "application/json, text/event-stream", .contentType: "application/json"]
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)
        #expect(exchange.status == .ok)
        #expect(!isHeaderMismatch(exchange))
    }

    @Test("Legacy resources/read not-found keeps the historical -32001")
    func legacyResourceNotFoundKeeps32001() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let headers: HTTPFields = [.accept: "application/json, text/event-stream", .contentType: "application/json"]

        // Legacy handshake first.
        let initBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let initExchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: initBody)
        let sessionID = try #require(initExchange.headerFields[.mcpSessionID])
        if case .sse(let stream) = initExchange.body { for await _ in stream {} }

        // Same not-found condition as the modern test, over the legacy session.
        var readHeaders = headers
        readHeaders[.mcpSessionID] = sessionID
        let readBody = try HTTPTransportTestHelpers.encode(
            JSONRPCMessage.request(
                id: 2, method: "resources/read", params: .object(["uri": .string("file:///nope.txt")])
            )
        )
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: readHeaders, body: readBody)
        guard case .sse(let stream) = exchange.body else {
            Issue.record("expected an SSE reply")
            return
        }
        var data = Data()
        for await chunk in stream { data.append(chunk) }
        let text = String(bytes: data, encoding: .utf8) ?? ""
        #expect(text.contains("-32001"))
        #expect(!text.contains("-32602"))
    }
}
#endif
