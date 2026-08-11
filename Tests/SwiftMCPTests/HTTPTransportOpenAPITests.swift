#if Server && OpenAPI
// swiftlint:disable force_cast
// Test-only: HTTP responses are known to be HTTPURLResponse.

import Testing
import SwiftCross
@testable import SwiftMCP

@Suite("HTTP Transport CORS, OpenAPI, and Error Cases")
struct HTTPTransportOpenAPITests {

    @Test("DELETE /mcp: removes session")
    func deleteSession() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(
            url: baseURL.appendingPathComponent("mcp")
        )
        let session = URLSession(configuration: .ephemeral)

        var deleteReq = URLRequest(url: baseURL.appendingPathComponent("mcp"))
        deleteReq.httpMethod = "DELETE"
        deleteReq.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")

        let (_, deleteResp) = try await session.data(for: deleteReq)
        #expect((deleteResp as! HTTPURLResponse).statusCode == 204)
    }

    @Test("DELETE /mcp: unknown session returns 404")
    func deleteUnknownSession() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
        request.httpMethod = "DELETE"
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Mcp-Session-Id")

        let (_, response) = try await session.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 404)
    }

    @Test("Resumable request streams expire after the retention interval")
    func expiredRequestStreamResume() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport(
            server: ResumableServer(),
            retentionInterval: 1.0
        )
        defer { Task { try? await transport.stop() } }

        let url = baseURL.appendingPathComponent("mcp")
        // One warm URLSession for the whole test: the retention interval doubles
        // as the idle-session TTL, so the gap between `initialize` completing and
        // the tool POST arriving must stay well under it. A cold ephemeral
        // URLSession can burn more than that just spinning up on a loaded CI
        // runner; reusing the keep-alive connection keeps the gap at
        // request-turnaround scale.
        let sharedSession = URLSession(configuration: .ephemeral)
        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(
            url: url, urlSession: sharedSession
        )

        let capture = HTTPTransportTestHelpers.openStreamingRequest(
            try HTTPTransportTestHelpers.streamablePOSTRequest(
                url: url,
                message: .request(
                    id: 9,
                    method: "tools/call",
                    params: [
                        "name": .string("slowPing"),
                        "arguments": .object([:]),
                        "_meta": .object([
                            "progressToken": .string("expiring-request")
                        ])
                    ]
                ),
                sessionID: sessionID
            ),
            urlSession: sharedSession
        )

        // Wait for the response head separately from the first event so each
        // phase gets its own budget and a failure names the phase that stalled.
        let connected = await HTTPTransportTestHelpers.waitForCondition {
            capture.response.value != nil
        }
        try #require(connected, "SSE response head never arrived — the POST never reached dispatch")
        let status = try #require(capture.response.value?.statusCode)
        try #require(
            status == 200,
            "tool POST rejected with \(status) — the session expired before the request arrived"
        )

        let sawProgress = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.notificationEvent(capture.events.value, method: "notifications/progress") != nil
        }
        #expect(sawProgress)
        let lastEventID = try #require(capture.events.value.last?.id)
        capture.task.cancel()

        // Sleep comfortably past the retention interval. Oversleeping is safe:
        // extra delay only makes the expiry below more certain.
        try? await Task.sleep(nanoseconds: 3_000_000_000)

        let resumeRequest = HTTPTransportTestHelpers.generalSSERequest(
            url: url, sessionID: sessionID, lastEventID: lastEventID
        )
        let (_, response) = try await sharedSession.data(for: resumeRequest)
        #expect((response as! HTTPURLResponse).statusCode == 404)
        #endif
    }

    @Test("OPTIONS returns CORS headers")
    func corsHeaders() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
        request.httpMethod = "OPTIONS"

        let (_, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        #expect(http.value(forHTTPHeaderField: "Access-Control-Allow-Methods")?.contains("POST") == true)
        #expect(http.value(forHTTPHeaderField: "Access-Control-Allow-Headers")?.contains("Content-Type") == true)
        #expect(http.value(forHTTPHeaderField: "Access-Control-Allow-Headers")?.contains("Mcp-Session-Id") == true)
    }

    @Test("GET /.well-known/ai-plugin.json returns manifest when serveOpenAPI is true")
    func aiPluginManifest() async throws {
        let server = Calculator()
        let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
        transport.serveOpenAPI = true
        try await transport.start()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "http://127.0.0.1:\(transport.port)/.well-known/ai-plugin.json")!

        let (data, response) = try await session.data(from: url)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["name_for_model"] as? String == "calculator")
        let api = json["api"] as? [String: Any]
        #expect((api?["url"] as? String)?.hasSuffix("/openapi.json") == true)
    }

    @Test("GET /.well-known/ai-plugin.json returns 404 when serveOpenAPI is false")
    func aiPluginManifestDisabled() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "\(baseURL.absoluteString)/.well-known/ai-plugin.json")!

        let (_, response) = try await session.data(from: url)
        #expect((response as! HTTPURLResponse).statusCode == 404)
    }

    @Test("GET /openapi.json returns spec with tool paths")
    func openAPISpec() async throws {
        let server = Calculator()
        let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
        transport.serveOpenAPI = true
        try await transport.start()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "http://127.0.0.1:\(transport.port)/openapi.json")!

        let (data, response) = try await session.data(from: url)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)

        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        #expect(json["openapi"] as? String == "3.1.0")
        let info = json["info"] as? [String: Any]
        #expect(info?["title"] as? String == "Calculator")
        let paths = json["paths"] as? [String: Any]
        #expect(paths?["/calculator/add"] != nil)
    }

    @Test("POST /{serverName}/{toolName} calls tool and returns result")
    func openAPIToolCall() async throws {
        let server = Calculator()
        let transport = HTTPSSETransport(server: server, host: "127.0.0.1", port: 0)
        transport.serveOpenAPI = true
        try await transport.start()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        let url = URL(string: "http://127.0.0.1:\(transport.port)/calculator/add")!

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["a": 3, "b": 7])

        let (data, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 200)
        let body = String(data: data, encoding: .utf8) ?? ""
        #expect(body.contains("10"))
    }

    @Test("POST /mcp: missing body returns 400")
    func missingBody() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")

        let (_, response) = try await session.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 400)
    }

    @Test("GET /sse: wrong Accept header returns 400")
    func wrongAcceptHeader() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: baseURL.appendingPathComponent("sse"))
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (_, response) = try await session.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 400)
    }

    @Test("POST /mcp: invalid protocol header returns 400")
    func invalidProtocolVersionHeader() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        let request = try HTTPTransportTestHelpers.streamablePOSTRequest(
            url: baseURL.appendingPathComponent("mcp"),
            message: HTTPTransportTestHelpers.initializeRequest(),
            protocolVersion: "bogus"
        )
        let (_, response) = try await session.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 400)
    }

    @Test("unknown path returns 404")
    func unknownPath() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        let (_, response) = try await session.data(from: baseURL.appendingPathComponent("nonexistent"))
        #expect((response as! HTTPURLResponse).statusCode == 404)
    }
}
// swiftlint:enable force_cast
#endif
