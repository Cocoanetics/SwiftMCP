//
//  NIOHTTPServerAdapter.swift
//  SwiftMCP
//
//  The swift-nio adapter behind the ``MCPHTTPEngine`` seam: the listening socket,
//  the HTTP/1 pipeline, and the shutdown that quiesces accepted connections
//  before the event loops go down. With `NIOHTTPChannelHandler.swift` (the
//  per-connection read/write loops), `NIOConnectionRegistry.swift` and
//  `NIOSSEConnection.swift` (the `Channel` liveness/close wiring) these are the
//  *only* files in the HTTP/SSE server linking the swift-nio server stack — the
//  engine (`HTTPSSETransport`, routing, sessions, SSE) is NIO-free. Swapping in
//  Network.framework means siblings of these files, not changes to the engine.
//

#if Server
import Foundation
import Logging
@preconcurrency import NIOConcurrencyHelpers
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
    /// The accepted connections and their handler tasks, quiesced by `shutdown()`.
    private let connections = NIOConnectionRegistry()
    /// The shutdown in progress once `shutdown()` ran; `waitUntilClosed()` joins it.
    private var shutdownTask: Task<Void, Error>?
    private let lock = NIOLock()

    /// How long `shutdown()` waits for handler tasks after cancelling them. A
    /// handler that ignores cancellation this long goes on without its loops.
    static let quiesceTimeout: TimeInterval = 5

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
        let connections = self.connections
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                // The listener's close completes on its own loop while a
                // connection it accepted just before may still be queued for
                // setup on another; the registry refuses it once the shutdown
                // has begun, so nothing serves a connection the quiesce missed.
                guard connections.register(channel) else {
                    return channel.close()
                }
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPLogger())
                }.flatMap {
                    // Translate NIO's HTTP/1 request/response parts to and from
                    // swift-http-types so the channel handler works in
                    // HTTPRequest / HTTPResponse / HTTPFields directly.
                    channel.pipeline.addHandler(HTTP1ToHTTPServerCodec(secure: false))
                }.flatMap {
                    channel.pipeline.addHandler(
                        NIOHTTPChannelHandler(engine: engine, logger: logger, connections: connections)
                    )
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
        } catch {
            // The group was created in `init`; a failed bind is the only path
            // on which nobody will ever call `shutdown()`, and each leaked
            // group is `System.coreCount` threads plus a kqueue descriptor.
            try? await shutdown()
            switch error {
            case let ioError as IOError:
                throw bindingError(for: ioError, host: engine.configuredHost, port: engine.configuredPort)
            default:
                logger.error("Server error: \(error)")
                throw TransportError.bindingFailed(error.localizedDescription)
            }
        }
    }

    /// Suspends until the listener has closed and, when `shutdown()` closed it,
    /// until the event-loop group is down too, so `run()` outlives the loops.
    func waitUntilClosed() async throws {
        try await channel?.closeFuture.get()
        if let shutdown = lock.withLock({ shutdownTask }) {
            try await shutdown.value
        }
    }

    /// Close the listener first, then the connections it accepted, and only then
    /// shut the event-loop group down. The group closes its loops concurrently:
    /// a connection the still-open listener accepted onto an already-closed loop
    /// was registered via `flatSubmit`, whose promise then leaked — fatal in
    /// debug builds — and a task scheduled onto a closed loop from a connection
    /// that outlived it (an SSE write, its post-response check, an engine-side
    /// `terminate()`) is NIO's "Cannot schedule tasks on an EventLoop that has
    /// already shut down", announced to become a forced crash. So every accepted
    /// channel is closed and its handler tasks are done before a loop goes down.
    /// Repeated calls join the first.
    func shutdown() async throws {
        let shutdown = lock.withLock { () -> Task<Void, Error> in
            if let shutdownTask { return shutdownTask }
            let task = Task { [self] in
                channel?.close(promise: nil)
                try? await channel?.closeFuture.get()
                await connections.quiesce(timeout: Self.quiesceTimeout)
                try await shutDownGroup()
            }
            shutdownTask = task
            return task
        }
        try await shutdown.value
    }

    private func shutDownGroup() async throws {
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
#endif
