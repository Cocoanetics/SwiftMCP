#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

@Suite("MRTR requestState security")
struct MRTRSecurityTests {

    @Test("Tampered requestState → -32602; state replayed on another tool → -32602")
    func stateVerification() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let first = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"),
                                   body: mrtrCallBody(tool: "askName"))
        let state = try #require(first["requestState"]?.stringValue)

        // Corrupt the first character of the payload segment. (Not the last
        // character: base64url's final char partly encodes ignored padding bits,
        // so flipping it can decode to identical bytes and still verify.)
        let tampered = (state.hasPrefix("A") ? "B" : "A") + state.dropFirst()
        let rejected = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"), body: mrtrCallBody(
            tool: "askName",
            extraParams: [
                "inputResponses": .object(["input-0": mrtrAcceptResponse(["name": .string("x")])]),
                "requestState": .string(tampered)
            ]
        ))
        #expect(rejected["__error_code"]?.intValue == -32602)

        // Genuine state, but presented on a different tool (digest mismatch).
        let crossed = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askTwo"), body: mrtrCallBody(
            tool: "askTwo",
            extraParams: [
                "inputResponses": .object(["input-0": mrtrAcceptResponse(["a": .string("x")])]),
                "requestState": .string(state)
            ]
        ))
        #expect(crossed["__error_code"]?.intValue == -32602)
    }

    @Test("A present-but-undecodable inputResponse → -32602, not a tool error")
    func malformedInputResponse() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let first = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"),
                                   body: mrtrCallBody(tool: "askName"))
        let state = try #require(first["requestState"]?.stringValue)

        // A bare string cannot decode into an ElicitationCreateResponse.
        let rejected = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"), body: mrtrCallBody(
            tool: "askName",
            extraParams: [
                "inputResponses": .object(["input-0": .string("not-a-response")]),
                "requestState": .string(state)
            ]
        ))
        #expect(rejected["__error_code"]?.intValue == -32602)
        #expect(rejected["__error_message"]?.stringValue?.contains("malformed inputResponse") == true)
    }

    @Test("A modern _meta request on a legacy session gets modern (MRTR) semantics")
    func modernMetaTrumpsLegacySession() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let plainHeaders: HTTPFields = [
            .accept: "application/json, text/event-stream", .contentType: "application/json"
        ]

        // Establish a legacy session first.
        let initBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let initExchange = await adapter.send(
            method: .post, path: "/mcp", headerFields: plainHeaders, body: initBody
        )
        let sessionID = try #require(initExchange.headerFields[.mcpSessionID])
        if case .sse(let stream) = initExchange.body { for await _ in stream {} }

        // Now a request that declares modern in `_meta` — even with the session
        // header attached, the body identity wins and MRTR semantics apply.
        var headers = mrtrCallHeaders(tool: "askName")
        headers[.mcpSessionID] = sessionID
        let result = try await mrtrSend(adapter, headers: headers, body: mrtrCallBody(tool: "askName"))
        #expect(result["resultType"]?.stringValue == "input_required")
    }

    @Test("Expired requestState → -32602")
    func expiredState() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // Craft an otherwise-valid payload that expired a minute ago, signed by
        // the same default signer the server verifies with.
        let toolParams: JSONValue = .object([
            "name": .string("askName"), "arguments": .object([:]), "_meta": mrtrModernMeta
        ])
        let payload = MRTRRequestStatePayload(
            iat: Date().timeIntervalSince1970 - 400,
            exp: Date().timeIntervalSince1970 - 60,
            principal: MRTRRequestState.principal(accessToken: nil),
            requestDigest: MRTRRequestState.requestDigest(method: "tools/call", params: toolParams),
            responses: [:]
        )
        let state = HMACRequestStateSigner.shared.sign(try JSONEncoder().encode(payload))

        let rejected = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"), body: mrtrCallBody(
            tool: "askName",
            extraParams: [
                "inputResponses": .object(["input-0": mrtrAcceptResponse(["name": .string("x")])]),
                "requestState": .string(state)
            ]
        ))
        #expect(rejected["__error_code"]?.intValue == -32602)
    }

    @Test("A principal-bound state presented by a different caller → -32602")
    func principalMismatch() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // First round authenticated as "tok-A" (via _meta accessToken).
        let metaA: JSONValue = .object([
            "io.modelcontextprotocol/protocolVersion": .string("2026-07-28"),
            "io.modelcontextprotocol/clientCapabilities": .object(["elicitation": .object([:])]),
            "accessToken": .string("tok-A")
        ])
        let first = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"),
                                   body: mrtrCallBody(tool: "askName", meta: metaA))
        let state = try #require(first["requestState"]?.stringValue)

        // Retry presents the same state without the principal → rejected.
        let rejected = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"), body: mrtrCallBody(
            tool: "askName",
            extraParams: [
                "inputResponses": .object(["input-0": mrtrAcceptResponse(["name": .string("x")])]),
                "requestState": .string(state)
            ]
        ))
        #expect(rejected["__error_code"]?.intValue == -32602)
    }

    @Test("prompts/get participates in MRTR round trips")
    func promptRoundTrip() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let headers: HTTPFields = [
            .accept: "application/json, text/event-stream", .contentType: "application/json",
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: "prompts/get", .mcpName: "greetPrompt"
        ]

        func promptBody(extra: JSONDictionary = [:]) throws -> Data {
            var params: JSONDictionary = [
                "name": .string("greetPrompt"), "arguments": .object([:]), "_meta": mrtrModernMeta
            ]
            for (key, value) in extra { params[key] = value }
            return try HTTPTransportTestHelpers.encode(
                JSONRPCMessage.request(id: 1, method: "prompts/get", params: .object(params))
            )
        }

        let first = try await mrtrSend(adapter, headers: headers, body: promptBody())
        #expect(first["resultType"]?.stringValue == "input_required")
        let state = try #require(first["requestState"]?.stringValue)

        let retry = try await mrtrSend(adapter, headers: headers, body: promptBody(extra: [
            "inputResponses": .object(["input-0": mrtrAcceptResponse(["name": .string("Oliver")])]),
            "requestState": .string(state)
        ]))
        let text = retry["messages"]?.arrayValue?.first?.dictionaryValue?["content"]?
            .dictionaryValue?["text"]?.stringValue
        #expect(text == "Greet Oliver")
    }

    @Test("Numeric arguments keep the request digest stable across rounds")
    func numericDigestStability() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        func body(extra: JSONDictionary = [:]) throws -> Data {
            var params: JSONDictionary = [
                "name": .string("labelValue"),
                "arguments": .object(["value": .double(3.14)]),
                "_meta": mrtrModernMeta
            ]
            for (key, value) in extra { params[key] = value }
            return try HTTPTransportTestHelpers.encode(
                JSONRPCMessage.request(id: 1, method: "tools/call", params: .object(params))
            )
        }

        let first = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "labelValue"), body: body())
        #expect(first["resultType"]?.stringValue == "input_required")
        let state = try #require(first["requestState"]?.stringValue)

        // The retry re-encodes the same numeric argument; the digest must match.
        let retry = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "labelValue"), body: body(extra: [
            "inputResponses": .object(["input-0": mrtrAcceptResponse(["label": .string("pi")])]),
            "requestState": .string(state)
        ]))
        let content = retry["content"]?.arrayValue?.first?.dictionaryValue
        #expect(content?["text"]?.stringValue == "pi:3.14")
    }

    // MARK: - Capability gating & legacy

    @Test("Without the elicitation capability the tool errors — never input_required")
    func capabilityGated() async throws {
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let bareMeta: JSONValue = .object([
            "io.modelcontextprotocol/protocolVersion": .string("2026-07-28")
        ])
        let result = try await mrtrSend(adapter, headers: mrtrCallHeaders(tool: "askName"),
                                    body: mrtrCallBody(tool: "askName", meta: bareMeta))
        #expect(result["resultType"]?.stringValue != "input_required")
        #expect(result["isError"]?.boolValue == true)
    }

    @Test("Legacy sessions keep the live elicitation path (no input_required)")
    func legacyUnaffected() async throws {
        // The legacy live path needs a connected client to answer; here it must
        // simply NOT produce input_required — it fails with the legacy error
        // because no client answers on a bare in-memory exchange.
        let transport = HTTPSSETransport(server: MRTRTestServer())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let headers: HTTPFields = [
            .accept: "application/json, text/event-stream", .contentType: "application/json"
        ]
        let initBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let initExchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: initBody)
        let sessionID = try #require(initExchange.headerFields[.mcpSessionID])
        if case .sse(let stream) = initExchange.body { for await _ in stream {} }

        var callHeaders = headers
        callHeaders[.mcpSessionID] = sessionID
        let body = try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(
            id: 2, method: "tools/call",
            params: .object(["name": .string("askName"), "arguments": .object([:])])
        ))
        let result = try await mrtrSend(adapter, headers: callHeaders, body: body)
        #expect(result["resultType"]?.stringValue != "input_required")
    }
}
#endif
