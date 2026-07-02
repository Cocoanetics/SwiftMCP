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

    @Test("POST /mcp: server/discover is answered before initialize, with no session")
    func discoverBeforeInitializeOverHTTP() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // No prior initialize and no Mcp-Session-Id: the modern negotiation entry
        // point must still be answered (the init gate exempts server/discover).
        let body = try HTTPTransportTestHelpers.encode(
            JSONRPCMessage.request(id: 1, method: "server/discover", params: nil)
        )
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: body)

        #expect(exchange.status == .ok)
        let text = await drain(exchange.body)
        #expect(text.contains("supportedVersions"))   // the discover result
        #expect(text.contains("serverInfo"))
    }

    @Test("POST /mcp: a batch hiding work behind server/discover is rejected pre-init")
    func discoverBatchSmuggleRejectedOverHTTP() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // A leading server/discover must NOT let a trailing tools/list run before
        // initialize: the whole pre-init batch is rejected (400), not processed.
        let batch = [
            JSONRPCMessage.request(id: 1, method: "server/discover", params: nil),
            JSONRPCMessage.request(id: 2, method: "tools/list", params: nil)
        ]
        let body = try JSONEncoder().encode(batch)
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: body)

        #expect(exchange.status == .badRequest)
        guard case .buffered = exchange.body else {
            Issue.record("expected a buffered rejection, got \(exchange.body)")
            return
        }
    }

    @Test("POST /mcp: a modern request is served sessionless (no Mcp-Session-Id, not -32004)")
    func modernPostServedSessionless() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // A modern client: MCP-Protocol-Version header + matching `_meta`, no session.
        let toolsList = JSONRPCMessage.request(
            id: 1, method: "tools/list",
            params: .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])])
        )
        var headers = jsonHeaders()
        headers[.mcpProtocolVersion] = "2026-07-28"
        let body = try HTTPTransportTestHelpers.encode(toolsList)
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)

        #expect(exchange.status == .ok)
        #expect(exchange.headerFields[.mcpSessionID] == nil)   // sessionless: no session echoed
        let text = await drain(exchange.body)
        #expect(text.contains("tools"))       // the tools/list result was served
        #expect(!text.contains("-32004"))     // not rejected as an unsupported version
    }

    @Test("A modern notification leaves no session behind (sessionless cleanup)")
    func modernNotificationIsSessionless() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)
        var headers = jsonHeaders()
        headers[.mcpProtocolVersion] = "2026-07-28"

        let note = JSONRPCMessage.notification(
            method: "notifications/cancelled",
            params: .object(["_meta": .object(["io.modelcontextprotocol/protocolVersion": .string("2026-07-28")])])
        )
        let body = try HTTPTransportTestHelpers.encode(note)
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: headers, body: body)

        #expect(exchange.status == .accepted)
        #expect(exchange.headerFields[.mcpSessionID] == nil)
        // The ephemeral session minted for routing is reclaimed synchronously, so
        // modern traffic accumulates no Session objects.
        let sessionCount = await transport.sessionManager.sessions.count
        #expect(sessionCount == 0)
    }

    @Test("GET /mcp declaring modern is 405 (standalone stream is legacy-only)")
    func modernGetIs405() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let exchange = await adapter.send(
            method: .get, path: "/mcp", headerFields: [.mcpProtocolVersion: "2026-07-28"]
        )
        #expect(exchange.status == .methodNotAllowed)
    }

    @Test("DELETE /mcp declaring modern is 405 (sessionless has no teardown)")
    func modernDeleteIs405() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let exchange = await adapter.send(
            method: .delete, path: "/mcp", headerFields: [.mcpProtocolVersion: "2026-07-28"]
        )
        #expect(exchange.status == .methodNotAllowed)
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
        // The SSE response carries the adapter's default CORS origin, same as NIO.
        #expect(getExchange.headerFields[.accessControlAllowOrigin] == "*")
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

    @Test("Oversized body is rejected with 413 before dispatch — like the NIO adapter")
    func oversizedBodyRejectedWith413() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        transport.maxMessageSize = 16                       // tiny limit for the test
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        let big = Data(repeating: 0x41, count: 64)          // 64 bytes > 16
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: big)

        #expect(exchange.status == .contentTooLarge)
        // The rejection is buffered and byte-identical to the NIO path: the message,
        // `Connection: close`, `text/plain`, plus the default CORS origin.
        guard case .buffered(let data?) = exchange.body else {
            Issue.record("expected a buffered 413, got \(exchange.body)")
            return
        }
        let text = String(bytes: data, encoding: .utf8) ?? ""
        #expect(text == "Request body exceeds maximum allowed size of 16 bytes.")
        #expect(exchange.headerFields[.connection] == "close")
        #expect(exchange.headerFields[.contentType] == "text/plain; charset=utf-8")
        #expect(exchange.headerFields[.accessControlAllowOrigin] == "*")
    }

    @Test("A body at or under the limit is dispatched normally")
    func bodyWithinLimitIsDispatched() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // Default 4 MB limit — a normal initialize is well under it and must route.
        let body = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let exchange = await adapter.send(method: .post, path: "/mcp", headerFields: jsonHeaders(), body: body)
        #expect(exchange.status == .ok)
    }

    @Test("Buffered responses carry the adapter's default headers, like NIO")
    func bufferedResponseCarriesDefaultHeaders() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        let adapter = InMemoryHTTPServerAdapter(engine: transport)

        // A 404 is a buffered reply with no body; the adapter still applies the
        // default CORS origin and a `Content-Length: 0`, matching the NIO adapter.
        let exchange = await adapter.send(method: .get, path: "/does-not-exist")
        #expect(exchange.status == .notFound)
        #expect(exchange.headerFields[.accessControlAllowOrigin] == "*")
        #expect(exchange.headerFields[.contentLength] == "0")
    }
}
#endif
