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
        // Decoupled transport: serve(over:) connects a dispatcher; each POST binds
        // its Mcp-Session-Id session + request stream and calls handle.
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

    @Test("Legacy SSE (/sse + /messages) works over serve(over:)")
    func legacySSEOverServe() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let server = HTTPServeTestServer()
        let transport = HTTPSSETransport(host: "127.0.0.1", port: 0)

        let serveTask = Task {
            try await server.serve(
                over: [transport],
                gracefulShutdownSignals: [],
                logger: Logger(label: "test.http.legacy")
            )
        }

        let bound = await HTTPTransportTestHelpers.waitForCondition { transport.port != 0 }
        #expect(bound)
        let baseURL = URL(string: "http://127.0.0.1:\(transport.port)")!

        // Open the general SSE stream and read its `endpoint` event.
        let capture = HTTPTransportTestHelpers.openStreamingRequest({
            var request = URLRequest(url: baseURL.appendingPathComponent("sse"))
            request.httpMethod = "GET"
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            return request
        }())

        let hasEndpoint = await HTTPTransportTestHelpers.waitForCondition {
            capture.events.value.contains { $0.event == "endpoint" }
        }
        #expect(hasEndpoint)
        let endpointEvent = try #require(capture.events.value.first { $0.event == "endpoint" })
        let messagesURL = try #require(URL(string: endpointEvent.data))

        // POST initialize to the legacy endpoint; the reply arrives on the stream.
        let postSession = URLSession(configuration: .ephemeral)
        var initRequest = URLRequest(url: messagesURL)
        initRequest.httpMethod = "POST"
        initRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initRequest.httpBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let (_, initResponse) = try await postSession.data(for: initRequest)
        #expect((initResponse as? HTTPURLResponse)?.statusCode == 202)
        #expect(await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.responseEvent(capture.events.value, id: 1) != nil
        })

        // POST ping; the reply also arrives on the general stream.
        var pingRequest = URLRequest(url: messagesURL)
        pingRequest.httpMethod = "POST"
        pingRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pingRequest.httpBody = try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(id: 3, method: "ping"))
        let (_, pingResponse) = try await postSession.data(for: pingRequest)
        #expect((pingResponse as? HTTPURLResponse)?.statusCode == 202)
        #expect(await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.responseEvent(capture.events.value, id: 3) != nil
        })

        capture.task.cancel()
        try await transport.stop()
        try await serveTask.value
        #endif
    }
}
#endif
