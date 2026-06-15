#if Server
import Foundation
import Testing
import SwiftCross
@testable import SwiftMCP

@Suite("Batching gate over HTTP")
struct BatchingGateHTTPTests {

    /// POST a raw JSON-RPC batch with neither an `Mcp-Session-Id` nor an
    /// `MCP-Protocol-Version` header — the brand-new-session path where the
    /// governing version is declared only inside the leading `initialize`.
    private func postHeaderlessBatch(
        to url: URL,
        messages: [JSONRPCMessage]
    ) async throws -> (HTTPURLResponse, Data) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONEncoder().encode(messages)

        let session = URLSession(configuration: .ephemeral)
        let (data, response) = try await session.data(for: request)
        let httpResponse = try #require(response as? HTTPURLResponse)
        return (httpResponse, data)
    }

    @Test("New-session batch is rejected when the leading initialize negotiates a no-batching version")
    func newSessionBatchRejected() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        // initializeRequest() declares protocolVersion 2025-11-25, which removed
        // batching — so the whole batch must be rejected even though no header or
        // session pins the version yet.
        let initialize = HTTPTransportTestHelpers.initializeRequest(id: 1)
        let ping = JSONRPCMessage.request(id: 2, method: "ping")

        let (response, data) = try await postHeaderlessBatch(
            to: baseURL.appendingPathComponent("mcp"),
            messages: [initialize, ping]
        )

        #expect(response.statusCode == 400)

        let message = try? JSONDecoder().decode(JSONRPCMessage.self, from: data)
        guard case .errorResponse(let errorResponse)? = message else {
            Issue.record("Expected a JSON-RPC error response, got: \(String(bytes: data, encoding: .utf8) ?? "")")
            return
        }
        #expect(errorResponse.error.code == -32600)
        #endif
    }
}
#endif
