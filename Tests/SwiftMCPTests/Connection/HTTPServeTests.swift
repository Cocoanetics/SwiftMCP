#if Server
import Testing
import Foundation
import Logging
@testable import SwiftMCP

/// A `Sendable` (actor) server with a tool that reports progress mid-call, used
/// to drive `serve(over: [HTTPSSETransport])` end-to-end over real HTTP.
@MCPServer(name: "HTTPServeTest")
actor HTTPServeTestServer {
    /// Reports progress, then returns "pong".
    @MCPTool(description: "Emits progress then returns pong")
    func slowPing() async -> String {
        await RequestContext.current?.reportProgress(0.5, total: 1.0, message: "halfway")
        return "pong"
    }
}

@Suite("serve(over: [HTTPSSETransport])")
struct HTTPServeTests {
    @Test("Initialize + tool call (with mid-call progress) over serve(over:)")
    func endToEnd() async throws {
        let server = HTTPServeTestServer()
        // Server-less transport: serve(over:) owns dispatch; the transport surfaces
        // each Mcp-Session-Id session as a scoped connection.
        let transport = HTTPSSETransport(host: "127.0.0.1", port: 0)

        let serveTask = Task {
            try await server.serve(
                over: [transport],
                gracefulShutdownSignals: [],
                logger: Logger(label: "test.http.serve")
            )
        }

        // serve runs the transport's run()/start() in its ServiceGroup; wait for
        // the listener to bind (port 0 → an assigned port).
        let bound = await HTTPTransportTestHelpers.waitForCondition { transport.port != 0 }
        #expect(bound)
        let url = URL(string: "http://127.0.0.1:\(transport.port)/mcp")!

        // initialize → request stream carries the initialize response.
        let (sessionID, initEvents) = try await HTTPTransportTestHelpers.initializeSession(url: url)
        #expect(HTTPTransportTestHelpers.responseEvent(initEvents, id: 1) != nil)

        // tools/call slowPing with a progress token → the request stream should
        // carry both a mid-call progress notification and the final response.
        let call = JSONRPCMessage.request(
            id: 2,
            method: "tools/call",
            params: [
                "name": .string("slowPing"),
                "arguments": .object([:]),
                "_meta": .object(["progressToken": .integer(42)])
            ]
        )
        let request = try HTTPTransportTestHelpers.streamablePOSTRequest(
            url: url,
            message: call,
            sessionID: sessionID
        )
        let (response, events) = try await HTTPTransportTestHelpers.readFiniteSSEResponse(request)

        #expect(response.statusCode == 200)
        // The tool response lands on this request's own SSE stream.
        let responseEvent = HTTPTransportTestHelpers.responseEvent(events, id: 2)
        #expect(responseEvent != nil)
        if let responseEvent, let message = try HTTPTransportTestHelpers.decodeEventMessage(responseEvent) {
            let encoded = try JSONEncoder().encode(message)
            #expect(String(data: encoded, encoding: .utf8)?.contains("pong") == true)
        }
        // The mid-call progress notification routed to the SAME request stream.
        #expect(HTTPTransportTestHelpers.notificationEvent(events, method: "notifications/progress") != nil)

        try await transport.stop()
        try await serveTask.value
    }
}
#endif
