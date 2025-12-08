import Testing
import NIOCore
import NIOEmbedded
import NIOHTTP1
@testable import SwiftMCP

@MCPServer(name: "HandlerTestServer", version: "1.0")
final class HandlerTestServer {
    @MCPTool(description: "Echo input")
    func echo(message: String) -> String {
        message
    }
}

@Suite("HTTPHandler chunked body handling", .tags(.unit))
struct HTTPHandlerChunkedBodyTests {

    @Test("Aggregates multi-chunk bodies before decoding")
    func aggregatesChunkedRequestBodies() async throws {
        let server = HandlerTestServer()
        let transport = HTTPSSETransport(server: server)

        let handler = TestHTTPHandler(transport: transport)

        let channel = EmbeddedChannel(handler: handler)
        defer { _ = try? channel.finish() }

        let head = HTTPRequestHead(version: .http1_1, method: .POST, uri: "/mcp")
        try channel.writeInbound(HTTPServerRequestPart.head(head))

        let firstChunk = channel.allocator.buffer(string: "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\",\"capabilities\":{},\"clientInfo\":{")
        let secondChunk = channel.allocator.buffer(string: "\"name\":\"TestClient\",\"version\":\"1.0\"}}}")

        try channel.writeInbound(HTTPServerRequestPart.body(firstChunk))
        try channel.writeInbound(HTTPServerRequestPart.body(secondChunk))
        try channel.writeInbound(HTTPServerRequestPart.end(nil))

        try await Task.sleep(nanoseconds: 100_000_000)

        #expect(handler.capturedBody?.contains("\"jsonrpc\":\"2.0\"") == true)
    }
}

final class TestHTTPHandler: HTTPHandler, @unchecked Sendable {

    private(set) var capturedBody: String?

    override func processRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        capturedBody = body?.getString(at: body?.readerIndex ?? 0, length: body?.readableBytes ?? 0)
    }
}
