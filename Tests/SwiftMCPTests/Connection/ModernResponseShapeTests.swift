#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// Exercises the modern (`2026-07-28`) response shape over the socket-free
/// ``InMemoryHTTPServerAdapter``: per-request SSE streams are non-resumable (no
/// `id:` anchors), carry `X-Accel-Buffering: no`, and an unknown method is
/// answered `404` + `-32601` before dispatch.
@Suite("Modern response shape (non-resumable SSE, 404)")
struct ModernResponseShapeTests {

    private func modernBody(method: String, extra: [String: JSONValue] = [:]) throws -> Data {
        var params: JSONDictionary = [
            "_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])
        ]
        for (key, value) in extra { params[key] = value }
        return try HTTPTransportTestHelpers.encode(
            JSONRPCMessage.request(id: 1, method: method, params: .object(params))
        )
    }

    private func modernHeaders(method: String, name: String? = nil) -> HTTPFields {
        var headers: HTTPFields = [
            .accept: "application/json, text/event-stream", .contentType: "application/json",
            .mcpProtocolVersion: "2026-07-28", .mcpMethod: method
        ]
        if let name { headers[.mcpName] = name }
        return headers
    }

    private func drain(_ exchange: InMemoryHTTPServerAdapter.Exchange) async -> String {
        guard case .sse(let stream) = exchange.body else { return "" }
        var data = Data()
        for await chunk in stream { data.append(chunk) }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    private func bufferedText(_ exchange: InMemoryHTTPServerAdapter.Exchange) -> String {
        guard case .buffered(let data?) = exchange.body else { return "" }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test("Modern SSE reply is non-resumable: no id: anchors, X-Accel-Buffering: no")
    func modernStreamShape() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let exchange = await adapter.send(
            method: .post, path: "/mcp",
            headerFields: modernHeaders(method: "tools/list"),
            body: try modernBody(method: "tools/list")
        )

        #expect(exchange.status == .ok)
        #expect(exchange.headerFields[.xAccelBuffering] == "no")
        #expect(exchange.headerFields[.mcpSessionID] == nil)

        let text = await drain(exchange)
        #expect(text.contains("tools"))     // the result arrived
        // No resume anchors: an SSE `id` field is a *line* starting with "id:",
        // so check line-anchored (a JSON body's "id":1 can never false-positive).
        let anchorLines = text.split(separator: "\n").filter { $0.hasPrefix("id:") }
        #expect(anchorLines.isEmpty)
    }

    @Test("Legacy SSE reply keeps its resume anchors and gets no X-Accel-Buffering")
    func legacyStreamShapeUnchanged() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let headers: HTTPFields = [
            .accept: "application/json, text/event-stream", .contentType: "application/json"
        ]
        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)

        #expect(exchange.status == .ok)
        #expect(exchange.headerFields[.xAccelBuffering] == nil)
        let text = await drain(exchange)
        #expect(text.contains("id: "))      // priming anchor still present for legacy
    }

    @Test("Modern legacy-only and unknown methods → 404 + -32601")
    func modernUnknownMethodIs404() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        for method in ["ping", "resources/subscribe", "frobnicate/run"] {
            let exchange = await adapter.send(
                method: .post, path: "/mcp",
                headerFields: modernHeaders(method: method),
                body: try modernBody(method: method)
            )
            #expect(exchange.status == .notFound, "expected 404 for \(method)")
            let text = bufferedText(exchange)
            #expect(text.contains("-32601"), "expected -32601 for \(method)")
        }
    }

    @Test("Legacy unknown method stays an in-band -32601 over 200")
    func legacyUnknownMethodInBand() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let headers: HTTPFields = [
            .accept: "application/json, text/event-stream", .contentType: "application/json"
        ]

        let initBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let initExchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: initBody)
        let sessionID = try #require(initExchange.headerFields[.mcpSessionID])
        _ = await drain(initExchange)

        var readHeaders = headers
        readHeaders[.mcpSessionID] = sessionID
        let body = try HTTPTransportTestHelpers.encode(
            JSONRPCMessage.request(id: 2, method: "frobnicate/run", params: nil)
        )
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: readHeaders, body: body)
        #expect(exchange.status == .ok)
        let text = await drain(exchange)
        #expect(text.contains("-32601"))
    }

    @Test("A modern notification with an unknown method still gets 202")
    func modernUnknownNotificationIs202() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        let note = JSONRPCMessage.notification(
            method: "notifications/whatever",
            params: .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])])
        )
        let exchange = await adapter.send(
            method: .post, path: "/mcp",
            headerFields: modernHeaders(method: "notifications/whatever"),
            body: try HTTPTransportTestHelpers.encode(note)
        )
        #expect(exchange.status == .accepted)
    }

    @Test("The modern method surface matches the dispatcher (no drift)")
    func modernMethodSurfaceMatchesDispatcher() async throws {
        let server = Calculator()
        // Every method in the set must dispatch to something other than the
        // -32601 fallback (malformed-params errors are fine — they prove the
        // method itself is routed).
        for method in ModernRequestMethods.known {
            let response = await server.handleMessage(.request(id: 1, method: method, params: nil))
            if case .errorResponse(let err) = response {
                #expect(err.error.code != -32601, "\(method) fell through to -32601 — set is stale")
            }
        }
        // And a made-up method must fall through, proving the fallback works.
        let unknown = await server.handleMessage(.request(id: 2, method: "frobnicate/run", params: nil))
        guard case .errorResponse(let err) = unknown else {
            Issue.record("expected -32601 for an unknown method")
            return
        }
        #expect(err.error.code == -32601)
    }
}
#endif
