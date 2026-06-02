#if Server
import Foundation
import Logging
import NIOCore
import NIOFoundationCompat
import NIOHTTP1
import NIOPosix

/**
 A transport that exposes an HTTP server with Server-Sent Events (SSE) and JSON-RPC endpoints.

 This transport is built on top of SwiftNIO and allows clients to connect via HTTP to interact
 with the MCPServer. It provides:

 - Server-Sent Events (SSE) for real-time updates
 - JSON-RPC over HTTP for command processing
 - Optional OpenAPI endpoints for API documentation
 - Configurable authorization
 - Keep-alive mechanisms
 */
public final class HTTPSSETransport: Transport, @unchecked Sendable {
    /// The MCP server instance that this transport exposes.
    public let server: MCPServer

    /// The hostname or IP address on which the HTTP server listens.
    public let host: String

    /// The port number on which the HTTP server listens.
    /// If initialized with `0`, the system will select an available port
    /// when the server starts. The actual bound port is then available
    /// via this property after ``start()`` completes.
    public internal(set) var port: Int

    /// Logger for logging transport events and errors.
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.HTTPSSETransport")

    internal let group: EventLoopGroup
    internal var channel: Channel?
    public var streamRetentionInterval: TimeInterval = 5 * 60
    internal lazy var sessionManager = SessionManager(
        transport: self,
        retentionInterval: streamRetentionInterval
    )
    internal var keepAliveTimer: DispatchSourceTimer?

    /// The HTTP router that dispatches incoming requests to route handlers.
    internal lazy var router: Router = buildRouter()

    /// Custom routes registered by the user via `addRoute`.
    internal var customRoutes: [HTTPRoute] = []

    /// Flag to determine whether to serve OpenAPI endpoints.
    public var serveOpenAPI: Bool = false

    /// Maximum allowed HTTP message size in bytes (defaults to 4 MB).
    public var maxMessageSize: Int = 4 * 1024 * 1024

    /// Result of an authorization check.
    public enum AuthorizationResult: Sendable {
        case authorized
        case unauthorized(String)
        case jweNotSupported(String)
    }

    /// A function type that handles authorization of requests.
    public typealias AuthorizationHandler = @Sendable (String?) -> AuthorizationResult

    /// Authorization handler for bearer tokens.
    public var authorizationHandler: AuthorizationHandler = { _ in return .authorized }

    /// Optional OAuth configuration. When set, incoming bearer tokens are
    /// validated using the provided settings and `.well-known` endpoints are
    /// served with the corresponding metadata.
    public var oauthConfiguration: OAuthConfiguration?

    /// Defines the available keep-alive modes for maintaining connections.
    public enum KeepAliveMode: Sendable {
        case none
        case sse
        case ping
    }

    /// The current keep-alive mode for the transport.
    public var keepAliveMode: KeepAliveMode = .ping {
        didSet {
            if oldValue != keepAliveMode {
                if keepAliveMode == .none {
                    stopKeepAliveTimer()
                } else {
                    startKeepAliveTimer()
                }
            }
        }
    }

    /// The number of active SSE channels currently connected to the server.
    var sseChannelCount: Int {
        get async { await sessionManager.channelCount }
    }

    // MARK: - Initialization

    public init(server: MCPServer, host: String = ProcessInfo.processInfo.hostName, port: Int = 8080) {
        self.server = server
        self.host = host
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    public convenience init(server: MCPServer) {
        self.init(server: server, host: ProcessInfo.processInfo.hostName, port: 8080)
    }

    // MARK: - Server Lifecycle

    public func start() async throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer {  channel in
                return channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPLogger())
                }.flatMap {
                    channel.pipeline.addHandler(HTTPHandler(transport: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)

        do {
            self.channel = try await bootstrap.bind(host: host, port: self.port).get()
            if let actualPort = self.channel?.localAddress?.port {
                self.port = actualPort
            }
            logger.info("Server started and listening on \(host):\(self.port)")
            startKeepAliveTimer()

            self.channel?.closeFuture.whenComplete { [logger] result in
                switch result {
                case .success:
                    logger.info("Server channel closed normally")
                case .failure(let error):
                    logger.error("Server channel closed with error: \(error)")
                }
            }
        } catch let error as IOError {
            throw bindingError(for: error)
        } catch {
            logger.error("Server error: \(error)")
            throw TransportError.bindingFailed(error.localizedDescription)
        }
    }

    public func run() async throws {
        try await start()
        try await channel?.closeFuture.get()
    }

    public func stop() async throws {
        logger.info("Stopping server...")
        stopKeepAliveTimer()

        await sessionManager.removeAllSessions()

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            group.shutdownGracefully { error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        logger.info("Server stopped")
    }

    // MARK: - Transport

    /// Send raw data to the client associated with the current `Session`.
    public func send(_ data: Data) async throws {
        precondition(Session.current != nil, "Attempted to send without an active session")
        let session = Session.current!

        let string = String(data: data, encoding: .utf8) ?? ""
        let message = SSEMessage(data: string)
        let routed = await sessionManager.routeSSEMessage(
            message,
            sessionID: session.id,
            preferredStreamID: Session.currentStreamContext?.streamID
        )
        if !routed {
            throw TransportError.bindingFailed("No routable SSE stream for session \(session.id)")
        }
    }

    // MARK: - Binding helpers

    private func bindingError(for error: IOError) -> TransportError {
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
