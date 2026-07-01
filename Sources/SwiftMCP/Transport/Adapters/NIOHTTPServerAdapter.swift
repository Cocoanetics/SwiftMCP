//
//  NIOHTTPServerAdapter.swift
//  SwiftMCP
//
//  The swift-nio adapter behind the ``MCPHTTPEngine`` seam: the listening socket,
//  the HTTP/1 pipeline, the per-connection read/write loops, and the `Channel`
//  liveness/close wiring. This is the *only* file in the HTTP/SSE server that
//  links the swift-nio server stack — the engine (`HTTPSSETransport`, routing,
//  sessions, SSE) is NIO-free. Swapping in Network.framework means writing a
//  sibling of this file, not touching the engine.
//

#if Server
import Foundation
import Logging
@preconcurrency import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOHTTPTypes
import NIOHTTPTypesHTTP1
import NIOPosix
import HTTPTypes

/// Owns the listening socket and event-loop group, and drives inbound requests
/// into the ``MCPHTTPEngine``.
final class NIOHTTPServerAdapter: @unchecked Sendable {
    private let engine: any MCPHTTPEngine
    private let logger: Logger
    private let group: EventLoopGroup
    private var channel: Channel?

    init(engine: any MCPHTTPEngine, logger: Logger) {
        self.engine = engine
        self.logger = logger
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    /// Bind the listener and return the actually-bound port (resolving an
    /// ephemeral `0`). The caller (engine) records it as its public `port`.
    func start() async throws -> Int {
        let engine = self.engine
        let logger = self.logger
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPLogger())
                }.flatMap {
                    // Translate NIO's HTTP/1 request/response parts to and from
                    // swift-http-types so the channel handler works in
                    // HTTPRequest / HTTPResponse / HTTPFields directly.
                    channel.pipeline.addHandler(HTTP1ToHTTPServerCodec(secure: false))
                }.flatMap {
                    channel.pipeline.addHandler(NIOHTTPChannelHandler(engine: engine, logger: logger))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)

        do {
            let channel = try await bootstrap.bind(host: engine.configuredHost, port: engine.configuredPort).get()
            self.channel = channel
            let boundPort = channel.localAddress?.port ?? engine.configuredPort
            logger.info("Server started and listening on \(engine.configuredHost):\(boundPort)")

            channel.closeFuture.whenComplete { [logger] result in
                switch result {
                case .success:
                    logger.info("Server channel closed normally")
                case .failure(let error):
                    logger.error("Server channel closed with error: \(error)")
                }
            }
            return boundPort
        } catch let error as IOError {
            throw bindingError(for: error, host: engine.configuredHost, port: engine.configuredPort)
        } catch {
            logger.error("Server error: \(error)")
            throw TransportError.bindingFailed(error.localizedDescription)
        }
    }

    /// Suspends until the listening channel closes.
    func waitUntilClosed() async throws {
        try await channel?.closeFuture.get()
    }

    /// Shut the listener down. Closing the group closes the listening channel,
    /// which completes `waitUntilClosed()`.
    func shutdown() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            group.shutdownGracefully { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func bindingError(for error: IOError, host: String, port: Int) -> TransportError {
        let errorMessage: String
        switch error.errnoCode {
        case EADDRINUSE:
            errorMessage = "Port \(port) is already in use. "
                + "Please choose a different port or ensure no other service is using this port."
        case EACCES:
            errorMessage = "Permission denied to bind to port \(port). This port may require elevated privileges."
        case EADDRNOTAVAIL:
            errorMessage = "The address \(host) is not available for binding."
        default:
            errorMessage = "Failed to bind to \(host):\(port). Error: \(error.localizedDescription)"
        }
        logger.error("\(errorMessage)")
        return TransportError.bindingFailed(errorMessage)
    }
}

/// The per-connection NIO channel handler: parses HTTP/1 request parts into an
/// `HTTPRequest` + an `AsyncStream<Data>` body, hands them to ``MCPHTTPEngine``,
/// and writes the ``EngineResponse`` back — buffered, or drained chunk-by-chunk
/// for SSE (one flush per event).
final class NIOHTTPChannelHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPRequestPart
    typealias OutboundOut = HTTPResponsePart

    private var requestState: RequestState = .idle
    private let engine: any MCPHTTPEngine
    private let logger: Logger

    init(engine: any MCPHTTPEngine, logger: Logger) {
        self.engine = engine
        self.logger = logger
    }

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

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let requestPart = unwrapInboundIn(data)

        switch (requestPart, requestState) {

        // HEAD — create stream and dispatch handler immediately
        case (.head(let head), _):
            let sizeLimit = engine.maxBodySize(for: head)
            if let contentLength = head.headerFields[.contentLength],
               let length = Int(contentLength), length > sizeLimit {
                logger.warning("Rejecting request with Content-Length \(length) > max \(sizeLimit)")
                rejectOversizedRequest(context: context, limit: sizeLimit)
                requestState = .rejected
                return
            }

            let (stream, continuation) = AsyncStream<Data>.makeStream()
            requestState = .streaming(head: head, continuation: continuation, bytesWritten: 0)
            dispatchRoute(context: context, head: head, bodyStream: stream)

        // BODY — yield chunk into the stream
        case (.body(let buffer), .streaming(let head, let continuation, let bytesWritten)):
            let sizeLimit = engine.maxBodySize(for: head)
            let newTotal = bytesWritten + buffer.readableBytes
            guard newTotal <= sizeLimit else {
                logger.warning("Rejecting request: body size \(newTotal) > max \(sizeLimit)")
                continuation.finish()
                rejectOversizedRequest(context: context, limit: sizeLimit)
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

    // MARK: - Dispatch

    private func dispatchRoute(context: ChannelHandlerContext, head: HTTPRequest, bodyStream: AsyncStream<Data>) {
        let channel = context.channel
        let engine = self.engine
        Task {
            let response = await engine.handle(head: head, bodyStream: bodyStream)
            await self.writeEngineResponse(response, to: channel, engine: engine)
        }
    }

    private func writeEngineResponse(
        _ response: EngineResponse,
        to channel: Channel,
        engine: any MCPHTTPEngine
    ) async {
        switch response.body {
        case .buffered(let data):
            let fields = HTTPResponseDefaults.buffered(response.headerFields, bodyLength: data?.count)
            let head = HTTPResponse(status: response.status, headerFields: fields)
            channel.write(HTTPResponsePart.head(head), promise: nil)
            if let data, !data.isEmpty {
                channel.write(HTTPResponsePart.body(channel.allocator.buffer(data: data)), promise: nil)
            }
            channel.writeAndFlush(HTTPResponsePart.end(nil), promise: nil)

        case .sse(let stream, let registration):
            // SSE: write the head immediately so the client can start consuming,
            // bind the live connection, then drain — flushing per event.
            let fields = HTTPResponseDefaults.streaming(response.headerFields)
            let head = HTTPResponse(status: response.status, headerFields: fields)
            channel.writeAndFlush(HTTPResponsePart.head(head), promise: nil)

            if let registration {
                let connection = NIOSSEConnection(channel: channel)
                if let token = await engine.registerConnection(connection, for: registration) {
                    channel.closeFuture.whenComplete { _ in
                        Task { await engine.connectionDisconnected(token) }
                    }
                }
            }

            for await chunk in stream {
                channel.write(HTTPResponsePart.body(channel.allocator.buffer(data: chunk)), promise: nil)
                channel.flush()
            }

            channel.writeAndFlush(HTTPResponsePart.end(nil), promise: nil)
        }
    }

    // MARK: - Oversize rejection

    private func rejectOversizedRequest(context: ChannelHandlerContext, limit: Int) {
        let fields: HTTPFields = [
            .connection: "close",
            .contentType: "text/plain; charset=utf-8"
        ]
        let message = "Request body exceeds maximum allowed size of \(limit) bytes."
        let body = context.channel.allocator.buffer(string: message)
        let resolved = HTTPResponseDefaults.buffered(fields, bodyLength: body.readableBytes)
        let head = HTTPResponse(status: .contentTooLarge, headerFields: resolved)
        context.channel.write(HTTPResponsePart.head(head), promise: nil)
        context.channel.write(HTTPResponsePart.body(body), promise: nil)
        context.channel.writeAndFlush(HTTPResponsePart.end(nil), promise: nil)
        context.close(promise: nil)
    }
}

/// An ``SSEConnection`` backed by a live NIO `Channel`.
final class NIOSSEConnection: SSEConnection {
    private let channel: Channel
    init(channel: Channel) { self.channel = channel }
    var isConnected: Bool { channel.isActive }
    func terminate() { channel.close(promise: nil) }
}
#endif
