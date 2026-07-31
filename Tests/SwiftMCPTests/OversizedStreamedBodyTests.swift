#if Server
import Foundation
import Testing

@testable import SwiftMCP

@Suite("Oversized streamed request bodies")
struct OversizedStreamedBodyTests {

    /// A chunked upload that exceeds `maxMessageSize` mid-stream is rejected
    /// with 413 — and, crucially, the already-dispatched route handler must
    /// not write a second response for the same request. That double
    /// response trips NIO's HTTP pipeline handler `fatalError`
    /// ("Unexpectedly received a response in state idle") and killed the
    /// whole server process before the `wasAborted` suppression existed.
    @Test("Server survives a chunked body exceeding the limit mid-stream")
    func serverSurvivesOversizedChunkedBody() async throws {
        #if canImport(FoundationNetworking)
        return
        #else
        let (transport, baseURL) = try await HTTPTransportTestHelpers.startTransport()
        defer { Task { try? await transport.stop() } }

        let mcpURL = baseURL.appendingPathComponent("mcp")

        // Stream 2 MiB against a 1 MiB limit with no Content-Length, so the
        // precheck cannot reject it and the oversize trips mid-body while
        // the dispatched handler is already consuming the stream.
        transport.maxMessageSize = 1 << 20

        var request = URLRequest(url: mcpURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBodyStream = InputStream(data: Data(repeating: 0x20, count: 2 << 20))

        let session = URLSession(configuration: .ephemeral)
        do {
            let (_, response) = try await session.data(for: request)
            let httpResponse = try #require(response as? HTTPURLResponse)
            #expect(httpResponse.statusCode == 413)
        } catch {
            // Also acceptable: the server closes the connection while the
            // client still has body to send, surfacing as a transport error.
        }

        // The server must still be alive and serving. Before the fix this
        // request never got an answer — the process had already died on the
        // pipeline fatalError.
        transport.maxMessageSize = 4 * 1024 * 1024
        var sanity = URLRequest(url: mcpURL)
        sanity.httpMethod = "POST"
        sanity.setValue("application/json", forHTTPHeaderField: "Content-Type")
        sanity.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        sanity.httpBody = try JSONEncoder().encode(
            HTTPTransportTestHelpers.initializeRequest(id: 1))

        let (_, aliveResponse) = try await session.data(for: sanity)
        let aliveHTTP = try #require(aliveResponse as? HTTPURLResponse)
        #expect(aliveHTTP.statusCode == 200)
        #endif
    }
}
#endif
