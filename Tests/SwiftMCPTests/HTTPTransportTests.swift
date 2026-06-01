// swiftlint:disable force_cast
// Test-only: HTTP responses are known to be `HTTPURLResponse` and decoded JSON
// payloads are known shapes. Force casts keep test code direct and readable.

import Testing
import SwiftCross
@testable import SwiftMCP

@Suite("HTTP Transport Streamable HTTP")
struct HTTPTransportTests {

    // MARK: - Modern Streamable HTTP

    @Test("POST /mcp: initialize returns SSE response stream")
    func modernInitialize() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let (response, events) = try await HTTPTransportTestHelpers.readFiniteSSEResponse(
            try HTTPTransportTestHelpers.streamablePOSTRequest(
                url: baseURL.appendingPathComponent("mcp"),
                message: HTTPTransportTestHelpers.initializeRequest()
            )
        )

        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Content-Type")?.contains("text/event-stream") == true)
        #expect(response.value(forHTTPHeaderField: "Mcp-Session-Id") != nil)

        let primingEvent = try #require(events.first)
        #expect(primingEvent.id != nil)
        #expect(primingEvent.data == "")

        let initEvent = try #require(HTTPTransportTestHelpers.responseEvent(events, id: 1))
        let message = try #require(try HTTPTransportTestHelpers.decodeEventMessage(initEvent))
        guard case .response(let responseData) = message,
              let result = responseData.result,
              let protocolVersion = result["protocolVersion"]?.stringValue else {
            Issue.record("Expected initialize response payload")
            return
        }

        #expect(protocolVersion == "2025-11-25")
        #endif
    }

    @Test("POST /mcp: initialize preserves negotiated fallback protocol version")
    func initializeNegotiatesFallbackProtocolVersion() async throws {
        try await assertInitializeProtocolVersion(version: "2025-03-26")
    }

    @Test("POST /mcp: initialize preserves negotiated intermediate protocol version")
    func initializeNegotiatesIntermediateProtocolVersion() async throws {
        try await assertInitializeProtocolVersion(version: "2025-06-18")
    }

    private func assertInitializeProtocolVersion(version: String) async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let request = try HTTPTransportTestHelpers.streamablePOSTRequest(
            url: baseURL.appendingPathComponent("mcp"),
            message: .request(
                id: 1,
                method: "initialize",
                params: [
                    "protocolVersion": .string(version),
                    "capabilities": .object([:]),
                    "clientInfo": .object([
                        "name": .string("TestClient"),
                        "version": .string("1.0")
                    ])
                ]
            ),
            protocolVersion: version
        )

        let (response, events) = try await HTTPTransportTestHelpers.readFiniteSSEResponse(request)
        #expect(response.statusCode == 200)

        let initEvent = try #require(HTTPTransportTestHelpers.responseEvent(events, id: 1))
        let message = try #require(try HTTPTransportTestHelpers.decodeEventMessage(initEvent))
        guard case .response(let responseData) = message,
              let result = responseData.result,
              let protocolVersion = result["protocolVersion"]?.stringValue else {
            Issue.record("Expected initialize response payload")
            return
        }

        #expect(protocolVersion == version)
        #endif
    }

    @Test("POST /mcp: initialize rejects unsupported protocol version")
    func initializeRejectsUnsupportedProtocolVersion() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let request = try HTTPTransportTestHelpers.streamablePOSTRequest(
            url: baseURL.appendingPathComponent("mcp"),
            message: .request(
                id: 1,
                method: "initialize",
                params: [
                    "protocolVersion": .string("2024-11-05"),
                    "capabilities": .object([:]),
                    "clientInfo": .object([
                        "name": .string("TestClient"),
                        "version": .string("1.0")
                    ])
                ]
            )
        )

        let (response, events) = try await HTTPTransportTestHelpers.readFiniteSSEResponse(request)
        #expect(response.statusCode == 200)

        let initEvent = try #require(HTTPTransportTestHelpers.errorResponseEvent(events, id: 1))
        let message = try #require(try HTTPTransportTestHelpers.decodeEventMessage(initEvent))
        guard case .errorResponse(let errorData) = message else {
            Issue.record("Expected initialize error response")
            return
        }

        #expect(errorData.error.code == -32602)
        #expect(errorData.error.message.contains("Unsupported protocol version"))
        #endif
    }

    @Test("POST /mcp: request stream returns response for existing session")
    func modernPing() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let url = baseURL.appendingPathComponent("mcp")
        let (sessionID, _) = try await HTTPTransportTestHelpers.initializeSession(url: url)

        let (response, events) = try await HTTPTransportTestHelpers.readFiniteSSEResponse(
            try HTTPTransportTestHelpers.streamablePOSTRequest(
                url: url,
                message: .request(id: 2, method: "ping"),
                sessionID: sessionID
            )
        )

        #expect(response.statusCode == 200)
        #expect(response.value(forHTTPHeaderField: "Mcp-Session-Id") == sessionID)
        #expect(HTTPTransportTestHelpers.responseEvent(events, id: 2) != nil)
        #endif
    }

    @Test("POST /mcp: missing session on non-initialize returns 400 without creating a session")
    func modernNonInitializeWithoutSessionRejected() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(id: 1, method: "ping"))

        let (_, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 400)
        #expect(http.value(forHTTPHeaderField: "Mcp-Session-Id") == nil)
        #expect(await transport.sessionManager.sessionIDs.isEmpty)
    }

    @Test("POST /mcp: unknown session returns 404")
    func modernUnknownSessionRejected() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Mcp-Session-Id")
        request.httpBody = try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(id: 1, method: "ping"))

        let (_, response) = try await session.data(for: request)
        let http = response as! HTTPURLResponse
        #expect(http.statusCode == 404)
        #expect(await transport.sessionManager.sessionIDs.isEmpty)
    }

    @Test("GET /mcp: missing session returns 400")
    func modernGeneralStreamRequiresSession() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        var request = URLRequest(url: baseURL.appendingPathComponent("mcp"))
        request.httpMethod = "GET"
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        let (_, response) = try await session.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 400)
    }

    @Test("GET /mcp: unknown session returns 404")
    func unknownModernSSESession() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        let request = HTTPTransportTestHelpers.generalSSERequest(
            url: baseURL.appendingPathComponent("mcp"),
            sessionID: UUID().uuidString
        )
        let (_, response) = try await session.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 404)
    }

}
// swiftlint:enable force_cast
