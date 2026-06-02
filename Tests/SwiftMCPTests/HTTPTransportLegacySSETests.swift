#if Server
// swiftlint:disable force_cast
// Test-only: HTTP responses are known to be HTTPURLResponse.

import Testing
import SwiftCross
@testable import SwiftMCP

@Suite("HTTP Transport Legacy SSE")
struct HTTPTransportLegacySSETests {

    @Test("Legacy SSE: connect, get endpoint, initialize, ping")
    func legacySSEFullFlow() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let capture = HTTPTransportTestHelpers.openStreamingRequest({
            var request = URLRequest(url: baseURL.appendingPathComponent("sse"))
            request.httpMethod = "GET"
            request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            return request
        }())

        let hasEndpoint = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.notificationEvent(capture.events.value, method: "endpoint") != nil
                || capture.events.value.contains { $0.event == "endpoint" }
        }

        let endpointEvent = try #require(capture.events.value.first(where: { $0.event == "endpoint" }))
        let messagesURL = try #require(URL(string: endpointEvent.data))
        #expect(hasEndpoint)
        #expect(messagesURL.path.hasPrefix("/messages/"))

        let postSession = URLSession(configuration: .ephemeral)
        var initRequest = URLRequest(url: messagesURL)
        initRequest.httpMethod = "POST"
        initRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        initRequest.httpBody = try HTTPTransportTestHelpers.encode(HTTPTransportTestHelpers.initializeRequest())
        let (_, initResponse) = try await postSession.data(for: initRequest)
        #expect((initResponse as! HTTPURLResponse).statusCode == 202)

        let initDelivered = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.responseEvent(capture.events.value, id: 1) != nil
        }
        #expect(initDelivered)

        var pingRequest = URLRequest(url: messagesURL)
        pingRequest.httpMethod = "POST"
        pingRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        pingRequest.httpBody = try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(id: 3, method: "ping"))
        let (_, pingResponse) = try await postSession.data(for: pingRequest)
        #expect((pingResponse as! HTTPURLResponse).statusCode == 202)

        let pingDelivered = await HTTPTransportTestHelpers.waitForCondition {
            HTTPTransportTestHelpers.responseEvent(capture.events.value, id: 3) != nil
        }
        #expect(pingDelivered)

        capture.task.cancel()
        #endif
    }

    @Test("Legacy SSE: unknown messages session returns 404")
    func legacySSEUnknownSessionRejected() async throws {
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let session = URLSession(configuration: .ephemeral)
        let url = baseURL
            .appendingPathComponent("messages")
            .appendingPathComponent(UUID().uuidString)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try HTTPTransportTestHelpers.encode(JSONRPCMessage.request(id: 1, method: "ping"))

        let (_, response) = try await session.data(for: request)
        #expect((response as! HTTPURLResponse).statusCode == 404)
    }
}
// swiftlint:enable force_cast
#endif
