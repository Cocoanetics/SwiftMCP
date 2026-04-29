import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@preconcurrency import NIOCore
import NIOHTTP1
import Logging


/// HTTP request handler for the SSE transport.
///
/// Manages the NIO state machine and dispatches to the router.
/// Body chunks are always streamed via `AsyncStream<Data>`. The dispatch
/// layer collects them into `Data` for buffered handlers, or forwards
/// the stream for streaming handlers.
final class HTTPHandler: NSObject, ChannelInboundHandler, Identifiable, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestState: RequestState = .idle
    private let transport: HTTPSSETransport
    let id = UUID()

    internal let logger = Logger(label: "com.cocoanetics.SwiftMCP.HTTPHandler")

    init(transport: HTTPSSETransport) {
        self.transport = transport
    }

    // MARK: - Channel Handler

    func channelInactive(context: ChannelHandlerContext) {
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        context.close(promise: nil)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let channelEvent = event as? ChannelEvent, channelEvent == .inputClosed {
            context.close(promise: nil)
            return
        }
        context.fireUserInboundEventTriggered(event)
    }

    // MARK: - State Machine

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let requestPart = unwrapInboundIn(data)

        switch (requestPart, requestState) {

        // HEAD — create stream and dispatch handler immediately
        case (.head(let head), _):
            let sizeLimit = maxBodySize(for: head)
            if let contentLength = head.headers.first(name: "content-length"),
               let length = Int(contentLength), length > sizeLimit {
                logger.warning("Rejecting request with Content-Length \(length) > max \(sizeLimit)")
                rejectOversizedRequest(context: context)
                requestState = .rejected
                return
            }

            let (stream, continuation) = AsyncStream<Data>.makeStream()
            requestState = .streaming(head: head, continuation: continuation, bytesWritten: 0)
            dispatchRoute(context: context, head: head, bodyStream: stream)

        // BODY — yield chunk into the stream
        case (.body(let buffer), .streaming(let head, let continuation, let bytesWritten)):
            let sizeLimit = maxBodySize(for: head)
            let newTotal = bytesWritten + buffer.readableBytes
            guard newTotal <= sizeLimit else {
                logger.warning("Rejecting request: body size \(newTotal) > max \(sizeLimit)")
                continuation.finish()
                rejectOversizedRequest(context: context)
                requestState = .rejected
                return
            }
            if let bytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes) {
                continuation.yield(Data(bytes))
            }
            requestState = .streaming(head: head, continuation: continuation, bytesWritten: newTotal)

        // END — finish the stream
        case (.end, .streaming(_, let continuation, _)):
            defer { requestState = .idle }
            continuation.finish()

        // Rejection / unexpected states
        case (.body, .rejected), (.end, .rejected):
            if case .end = requestPart { requestState = .idle }
        case (.body, _):
            logger.warning("Received unexpected body without a valid head")
        case (.end, .idle):
            logger.warning("Received end without prior request state")
        }
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }

    // MARK: - Route Dispatch

    /// Match the route and dispatch the handler. For buffered handlers, the body
    /// stream is collected into `Data` first. For streaming handlers, the stream
    /// is passed directly.
    private func dispatchRoute(context: ChannelHandlerContext, head: HTTPRequestHead, bodyStream: AsyncStream<Data>) {
        let channel = context.channel
        let (path, queryParams) = parseURI(head.uri)

        guard let method = convertMethod(head.method),
              let routeMatch = transport.router.match(method: method, path: path) else {
            sendResponse(channel: channel, status: .notFound)
            return
        }

        let handler = routeMatch.route.handler

        let request = HTTPRouteRequest<AsyncStream<Data>>(
            method: method, uri: head.uri, path: path,
            headers: convertHeaders(head.headers), body: bodyStream,
            pathParams: routeMatch.pathParams, queryParams: queryParams
        )

        Task {
            do {
                let response = try await handler(self.transport, request)

                // For SSE streaming responses, register the NIO channel.
                if response.bodyStream != nil {
                    if let streamInfo = response.streamInfo {
                        self.transport.registerSSEChannel(
                            channel,
                            sessionID: streamInfo.sessionID,
                            streamID: streamInfo.streamID
                        )
                    }
                }

                await self.writeRouteResponse(response, to: channel)
            } catch {
                self.logger.error("Route handler error: \(error)")
                let errorResponse = RouteResponse(status: .internalServerError, body: Data("Internal Server Error".utf8))
                await self.writeRouteResponse(errorResponse, to: channel)
            }
        }
    }

    // MARK: - Response Writing

    private func writeRouteResponse(_ response: RouteResponse, to channel: Channel) async {
        var nioHeaders = HTTPHeaders()
        for (name, value) in response.headers {
            nioHeaders.add(name: name, value: value)
        }
        if nioHeaders["Access-Control-Allow-Origin"].isEmpty {
            nioHeaders.add(name: "Access-Control-Allow-Origin", value: "*")
        }

        let status = nioStatus(response.status)

        if let stream = response.bodyStream {
            // For streaming responses (SSE), don't set Content-Length.
            // Write head immediately so the client can start consuming.
            let head = HTTPResponseHead(version: .http1_1, status: status, headers: nioHeaders)
            channel.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)

            for await chunk in stream {
                let buffer = channel.allocator.buffer(data: chunk)
                channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
                channel.flush()
            }

            channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
        } else {
            var body: ByteBuffer? = nil
            if let data = response.body {
                body = channel.allocator.buffer(data: data)
            }
            sendResponse(channel: channel, status: status, headers: nioHeaders, body: body)
        }
    }

    // MARK: - Helpers

    private func maxBodySize(for head: HTTPRequestHead) -> Int {
        if let method = convertMethod(head.method) {
            let (path, _) = parseURI(head.uri)
            if let match = transport.router.match(method: method, path: path),
               let perRoute = match.route.maxBodySize {
                return perRoute
            }
        }
        return transport.maxMessageSize
    }

    private func rejectOversizedRequest(context: ChannelHandlerContext) {
        var headers = HTTPHeaders()
        headers.add(name: "Connection", value: "close")
        headers.add(name: "Content-Type", value: "text/plain; charset=utf-8")
        let message = "Request body exceeds maximum allowed size of \(transport.maxMessageSize) bytes."
        var buffer = context.channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        sendResponse(channel: context.channel, status: .payloadTooLarge, headers: headers, body: buffer)
        context.close(promise: nil)
    }

    private func convertMethod(_ nioMethod: NIOHTTP1.HTTPMethod) -> RouteMethod? {
        switch nioMethod {
        case .GET: return .GET
        case .POST: return .POST
        case .PUT: return .PUT
        case .DELETE: return .DELETE
        case .PATCH: return .PATCH
        case .OPTIONS: return .OPTIONS
        case .HEAD: return .HEAD
        default: return nil
        }
    }

    private func nioStatus(_ status: HTTPStatus) -> HTTPResponseStatus {
        HTTPResponseStatus(statusCode: status.rawValue)
    }

    private func parseURI(_ uri: String) -> (path: String, queryParams: [(String, String)]) {
        guard let questionMark = uri.firstIndex(of: "?") else {
            return (uri, [])
        }
        let path = String(uri[..<questionMark])
        let queryString = String(uri[uri.index(after: questionMark)...])
        let queryParams = queryString.split(separator: "&").compactMap { pair -> (String, String)? in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let key = parts.first.flatMap({ String($0).removingPercentEncoding }) else { return nil }
            let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? "") : ""
            return (key, value)
        }
        return (path, queryParams)
    }

    private func convertHeaders(_ nioHeaders: HTTPHeaders) -> [(String, String)] {
        nioHeaders.map { ($0.name, $0.value) }
    }

    static func responseHeadersApplyingDefaults(
        _ headers: [(String, String)],
        bodyLength: Int?
    ) -> [(String, String)] {
        var responseHeaders = HTTPHeaders()
        for (name, value) in headers {
            responseHeaders.add(name: name, value: value)
        }

        if responseHeaders["Access-Control-Allow-Origin"].isEmpty {
            responseHeaders.add(name: "Access-Control-Allow-Origin", value: "*")
        }

        if let bodyLength {
            if responseHeaders["Content-Type"].isEmpty {
                responseHeaders.add(name: "Content-Type", value: "text/plain; charset=utf-8")
            }
            if responseHeaders["Content-Length"].isEmpty {
                responseHeaders.add(name: "Content-Length", value: "\(bodyLength)")
            }
        } else if responseHeaders["Content-Length"].isEmpty {
            responseHeaders.add(name: "Content-Length", value: "0")
        }

        return responseHeaders.map { ($0.name, $0.value) }
    }

    private func sendResponse(channel: Channel, status: HTTPResponseStatus, headers: HTTPHeaders? = nil, body: ByteBuffer? = nil) {
        let headerPairs = (headers ?? HTTPHeaders()).map { ($0.name, $0.value) }
        let resolvedHeaders = Self.responseHeadersApplyingDefaults(headerPairs, bodyLength: body?.readableBytes)

        var responseHeaders = HTTPHeaders()
        for (name, value) in resolvedHeaders {
            responseHeaders.add(name: name, value: value)
        }

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: responseHeaders)
        channel.write(HTTPServerResponsePart.head(head), promise: nil)
        if let body = body {
            channel.write(HTTPServerResponsePart.body(.byteBuffer(body)), promise: nil)
        }
        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
    }
}
