#if Server
import SwiftCross
@preconcurrency import NIOCore
import NIOFoundationCompat
import NIOHTTPTypes
import HTTPTypes
import Logging

/// HTTP request handler for the SSE transport.
///
/// Consumes swift-http-types request parts (translated from NIO's HTTP/1 parts
/// by the upstream `HTTP1ToHTTPServerCodec`) and dispatches to the router, so
/// it works in `HTTPRequest` / `HTTPResponse` / `HTTPFields` directly. Body
/// chunks are always streamed via `AsyncStream<Data>`. The dispatch layer
/// collects them into `Data` for buffered handlers, or forwards the stream for
/// streaming handlers.
final class HTTPHandler: NSObject, ChannelInboundHandler, Identifiable, @unchecked Sendable {
    typealias InboundIn = HTTPRequestPart
    typealias OutboundOut = HTTPResponsePart

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
            if let contentLength = head.headerFields[.contentLength],
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
    private func dispatchRoute(context: ChannelHandlerContext, head: HTTPRequest, bodyStream: AsyncStream<Data>) {
        let channel = context.channel
        let uri = head.path ?? "/"
        let (path, queryParams) = parseURI(uri)

        guard let routeMatch = transport.router.match(method: head.method, path: path) else {
            sendResponse(channel: channel, status: .notFound)
            return
        }

        let handler = routeMatch.route.handler

        let request = HTTPRouteRequest<AsyncStream<Data>>(
            method: head.method, uri: uri, path: path,
            headerFields: Self.requestHeaderFields(from: head), body: bodyStream,
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
        if let stream = response.bodyStream {
            // For streaming responses (SSE), don't set Content-Length.
            // Write head immediately so the client can start consuming.
            var fields = response.headerFields
            if fields[.accessControlAllowOrigin] == nil {
                fields[.accessControlAllowOrigin] = "*"
            }
            let head = HTTPResponse(status: response.status, headerFields: fields)
            channel.writeAndFlush(HTTPResponsePart.head(head), promise: nil)

            for await chunk in stream {
                let buffer = channel.allocator.buffer(data: chunk)
                channel.write(HTTPResponsePart.body(buffer), promise: nil)
                channel.flush()
            }

            channel.writeAndFlush(HTTPResponsePart.end(nil), promise: nil)
        } else {
            var body: ByteBuffer?
            if let data = response.body {
                body = channel.allocator.buffer(data: data)
            }
            sendResponse(channel: channel, status: response.status, fields: response.headerFields, body: body)
        }
    }

    // MARK: - Helpers

    private func maxBodySize(for head: HTTPRequest) -> Int {
        let (path, _) = parseURI(head.path ?? "/")
        if let match = transport.router.match(method: head.method, path: path),
           let perRoute = match.route.maxBodySize {
            return perRoute
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
        sendResponse(channel: context.channel, status: .contentTooLarge, fields: fields, body: buffer)
        context.close(promise: nil)
    }

    /// The request's header fields, re-exposing the `Host` header that the HTTP/1
    /// codec lifts into the `:authority` pseudo-header, so routes that read
    /// `header("Host")` keep working.
    static func requestHeaderFields(from request: HTTPRequest) -> HTTPFields {
        var fields = request.headerFields
        // `HTTPField.Name.host` is unavailable (HTTP/2 maps Host to `:authority`),
        // so reconstruct the literal `Host` field name to re-expose it.
        let hostName = HTTPField.Name("Host")!
        if let authority = request.authority, fields[hostName] == nil {
            fields[hostName] = authority
        }
        return fields
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

    private func sendResponse(
        channel: Channel,
        status: HTTPResponse.Status,
        fields: HTTPFields = [:],
        body: ByteBuffer? = nil
    ) {
        let resolvedFields = Self.responseFieldsApplyingDefaults(fields, bodyLength: body?.readableBytes)
        let head = HTTPResponse(status: status, headerFields: resolvedFields)
        channel.write(HTTPResponsePart.head(head), promise: nil)
        if let body = body {
            channel.write(HTTPResponsePart.body(body), promise: nil)
        }
        channel.writeAndFlush(HTTPResponsePart.end(nil), promise: nil)
    }
}
#endif
