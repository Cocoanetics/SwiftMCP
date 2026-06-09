#if Server
import SwiftCross
@preconcurrency import NIOCore
import NIOHTTP1
import HTTPTypes
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
            headerFields: convertHeaders(head.headers), body: bodyStream,
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
                let errorResponse = RouteResponse(
                    status: .internalServerError,
                    body: Data("Internal Server Error".utf8)
                )
                await self.writeRouteResponse(errorResponse, to: channel)
            }
        }
    }

    // MARK: - Response Writing

    private func writeRouteResponse(_ response: RouteResponse, to channel: Channel) async {
        let status = nioStatus(response.status)

        if let stream = response.bodyStream {
            // For streaming responses (SSE), don't set Content-Length.
            // Write head immediately so the client can start consuming.
            var fields = response.headerFields
            if fields[.accessControlAllowOrigin] == nil {
                fields[.accessControlAllowOrigin] = "*"
            }
            let head = HTTPResponseHead(version: .http1_1, status: status, headers: Self.nioHeaders(from: fields))
            channel.writeAndFlush(HTTPServerResponsePart.head(head), promise: nil)

            for await chunk in stream {
                let buffer = channel.allocator.buffer(data: chunk)
                channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
                channel.flush()
            }

            channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
        } else {
            var body: ByteBuffer?
            if let data = response.body {
                body = channel.allocator.buffer(data: data)
            }
            sendResponse(channel: channel, status: status, fields: response.headerFields, body: body)
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
        let fields: HTTPFields = [
            .connection: "close",
            .contentType: "text/plain; charset=utf-8"
        ]
        let message = "Request body exceeds maximum allowed size of \(transport.maxMessageSize) bytes."
        var buffer = context.channel.allocator.buffer(capacity: message.utf8.count)
        buffer.writeString(message)
        sendResponse(channel: context.channel, status: .payloadTooLarge, fields: fields, body: buffer)
        context.close(promise: nil)
    }

    private func convertMethod(_ nioMethod: NIOHTTP1.HTTPMethod) -> HTTPRequest.Method? {
        switch nioMethod {
        case .GET: return .get
        case .POST: return .post
        case .PUT: return .put
        case .DELETE: return .delete
        case .PATCH: return .patch
        case .OPTIONS: return .options
        case .HEAD: return .head
        default: return nil
        }
    }

    private func nioStatus(_ status: HTTPResponse.Status) -> HTTPResponseStatus {
        HTTPResponseStatus(statusCode: status.code)
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

    private func convertHeaders(_ nioHeaders: HTTPHeaders) -> HTTPFields {
        var fields = HTTPFields()
        for (name, value) in nioHeaders {
            guard let fieldName = HTTPField.Name(name) else { continue }
            fields.append(HTTPField(name: fieldName, value: value))
        }
        return fields
    }

    /// Apply the framework's default response fields (CORS, Content-Type, Content-Length)
    /// without overwriting values the route already provided. `HTTPFields` is
    /// case-insensitive and replaces rather than appends, so defaults can never
    /// duplicate an existing field.
    static func responseFieldsApplyingDefaults(
        _ fields: HTTPFields,
        bodyLength: Int?
    ) -> HTTPFields {
        var fields = fields

        if fields[.accessControlAllowOrigin] == nil {
            fields[.accessControlAllowOrigin] = "*"
        }

        if let bodyLength {
            if fields[.contentType] == nil {
                fields[.contentType] = "text/plain; charset=utf-8"
            }
            if fields[.contentLength] == nil {
                fields[.contentLength] = "\(bodyLength)"
            }
        } else if fields[.contentLength] == nil {
            fields[.contentLength] = "0"
        }

        return fields
    }

    /// Convert `HTTPFields` to NIO `HTTPHeaders`, preserving original field-name casing and order.
    static func nioHeaders(from fields: HTTPFields) -> HTTPHeaders {
        var headers = HTTPHeaders()
        for field in fields {
            headers.add(name: field.name.rawName, value: field.value)
        }
        return headers
    }

    private func sendResponse(
        channel: Channel,
        status: HTTPResponseStatus,
        fields: HTTPFields = [:],
        body: ByteBuffer? = nil
    ) {
        let resolvedFields = Self.responseFieldsApplyingDefaults(fields, bodyLength: body?.readableBytes)
        let head = HTTPResponseHead(version: .http1_1, status: status, headers: Self.nioHeaders(from: resolvedFields))
        channel.write(HTTPServerResponsePart.head(head), promise: nil)
        if let body = body {
            channel.write(HTTPServerResponsePart.body(.byteBuffer(body)), promise: nil)
        }
        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
    }
}
#endif
