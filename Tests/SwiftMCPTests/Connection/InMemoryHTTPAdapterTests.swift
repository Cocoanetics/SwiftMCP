#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

/// Exercises the full MCP HTTP/SSE engine through ``InMemoryHTTPServerAdapter`` —
/// no swift-nio, no socket — proving the engine is transport-agnostic behind the
/// ``MCPHTTPEngine`` seam.
@Suite("In-memory HTTP adapter (NIO-free engine)")
struct InMemoryHTTPAdapterTests {

    private func jsonHeaders() -> HTTPFields {
        [.accept: "application/json, text/event-stream", .contentType: "application/json"]
    }

    private func drain(_ body: InMemoryHTTPServerAdapter.ExchangeBody) async -> String {
        guard case .sse(let stream) = body else { return "" }
        var data = Data()
        for await chunk in stream { data.append(chunk) }
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    @Test("POST /mcp initialize is served end-to-end with no socket")
    func initializeOverInMemoryAdapter() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: body)

        #expect(exchange.status == .ok)
        #expect(exchange.headerFields[.mcpSessionID] != nil)

        let text = await drain(exchange.body)
        #expect(text.contains("data:"))            // SSE-framed
        #expect(text.contains("serverInfo"))        // the initialize result
        #expect(text.contains("protocolVersion"))
    }

    @Test("Unknown path returns 404 through the seam")
    func unknownPathReturns404() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let exchange = await adapter.send(method: .get, path: "/does-not-exist")
        #expect(exchange.status == .notFound)
        guard case .buffered = exchange.body else {
            Issue.record("expected a buffered 404, got \(exchange.body)")
            return
        }
    }

    @Test("GET /mcp primes an SSE stream; terminate disconnects it")
    func generalStreamOverInMemoryAdapter() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // Initialize to open a session.
        let initBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let initExchange = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: initBody)
        let sessionID = try #require(initExchange.headerFields[.mcpSessionID])
        _ = await drain(initExchange.body)

        // Open the general SSE stream for that session.
        let getExchange = await adapter.send(
            method: .get, path: "/mcp",
            headerFields: [.accept: "text/event-stream", .mcpSessionID: sessionID]
        )
        #expect(getExchange.status == .ok)
        let connection = try #require(getExchange.connection)
        #expect(connection.isConnected)

        guard case .sse(let stream) = getExchange.body else {
            Issue.record("expected an SSE response")
            return
        }
        // The priming event carries the `<uuid>:<sequence>` resume anchor.
        var iterator = stream.makeAsyncIterator()
        let priming = await iterator.next()
        let primingText = String(bytes: priming ?? Data(), encoding: .utf8) ?? ""
        #expect(primingText.contains("id:"))

        // Terminating the connection drops it; the engine retains the stream.
        connection.terminate()
        #expect(!connection.isConnected)
    }
}
#endif
