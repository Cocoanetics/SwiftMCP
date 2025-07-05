import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOFoundationCompat
import Logging

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
    public let port: Int

    /// Logger for logging transport events and errors.
    public var logger = Logger(label: "com.cocoanetics.SwiftMCP.HTTPSSETransport")

    private let group: EventLoopGroup
    private var channel: Channel?
    internal lazy var sessionManager = SessionManager(transport: self)
    private var keepAliveTimer: DispatchSourceTimer?

    /// Flag to determine whether to serve OpenAPI endpoints.
    public var serveOpenAPI: Bool = false

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

    /// Perform authorization using either the OAuth configuration or the
    /// synchronous ``authorizationHandler`` closure.
    func authorize(_ token: String?, sessionID: UUID?) async -> AuthorizationResult {
        // Check for JWE tokens first (5 segments: header.encrypted_key.iv.ciphertext.tag)
        if let token = token {
            let segments = token.split(separator: ".")
            if segments.count == 5 {
                // JWE token detected - only allow in proxy mode
                if let oauthConfiguration = oauthConfiguration, oauthConfiguration.transparentProxy {
                    // In proxy mode, we can handle JWE tokens by proxying them
                    // Continue with normal validation
                } else {
                    // In non-proxy mode, JWE tokens are not supported
                    let audience = oauthConfiguration?.audience ?? "your-api"
                    return .jweNotSupported("Encrypted (JWE) tokens are not supported. Use a signed JWT (JWS) with audience=\(audience)")
                }
            }
        }
        
        // 1. If we have a session ID, check token against session-stored value
        if let id = sessionID {
            let session = await sessionManager.session(id: id)
            if let stored = session.accessToken {
                if stored == token, (session.accessTokenExpiry ?? Date.distantFuture) > Date() {
                    return .authorized
                } else {
                    return .unauthorized("Invalid or expired token")
                }
            } else if let token { 
                // First time we see a token for this session - validate it before accepting
                let isValid = await validateNewToken(token)
                if isValid {
                    session.accessToken = token
                    // Without expires_in we can't know exact lifetime; fall back to 24 h.
                    session.accessTokenExpiry = Date().addingTimeInterval(24 * 60 * 60)
                    
                    // Fetch and store user info if we have OAuth configuration
                    if let oauthConfiguration = oauthConfiguration {
                        await sessionManager.fetchAndStoreUserInfo(for: id, oauthConfiguration: oauthConfiguration)
                    }
                    
                    return .authorized
                } else {
                    return .unauthorized("Invalid token - token exchange required")
                }
            } else {
                return .unauthorized("No token provided")
            }
        }

        // 2. If we don't have a sessionID, see if we can locate a session by token.
        if let token, sessionID == nil {
            if await sessionManager.session(forToken: token) != nil {
                return .authorized
            }
        }

        // 3. For tokens without session context, validate them
        if let token {
            let isValid = await validateNewToken(token)
            return isValid ? .authorized : .unauthorized("Invalid token - token exchange required")
        }

        // 4. Otherwise use legacy handler
        return authorizationHandler(token)
    }
    
    /// Validate a new token using OAuth configuration or authorization handler
    private func validateNewToken(_ token: String) async -> Bool {
        // If we have OAuth configuration, use its validation
        if let oauthConfiguration {
            // In transparent proxy mode, only accept tokens that are already stored in a session
            // This ensures we only trust tokens that came through our proxy
            if oauthConfiguration.transparentProxy {
                // Check if this token is already stored in any session
                if await sessionManager.session(forToken: token) != nil {
                    return true
                }
            }
            
            // Try OAuth validation for non-proxy mode
            let oauthValid = await oauthConfiguration.validate(token: token)
            if oauthValid {
                return true
            }
            
            return false
        }
        
        // Fallback to authorization handler
        switch authorizationHandler(token) {
        case .authorized:
            return true
        case .unauthorized:
            return false
        case .jweNotSupported:
            return false
        }
    }

    /// Defines the available keep-alive modes for maintaining connections.
    public enum KeepAliveMode: Sendable {
        case none
        case sse
        case ping
    }

    /// The current keep-alive mode for the transport.
    public var keepAliveMode: KeepAliveMode = .none {
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

    /// Number used as identifier for output-bound JSONRPCRequests, e.g. ping
    fileprivate var sequenceNumber = 1

    /// The number of active SSE channels currently connected to the server.
    var sseChannelCount: Int {
        get async { await sessionManager.channelCount }
    }


    // MARK: - Initialization

    public init(server: MCPServer, host: String = String.localHostname, port: Int = 8080) {
        self.server = server
        self.host = host
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }

    public convenience init(server: MCPServer) {
        self.init(server: server, host: String.localHostname, port: 8080)
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
            self.channel = try await bootstrap.bind(host: host, port: port).get()
            logger.info("Server started and listening on \(host):\(port)")
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
            let errorMessage: String
            switch error.errnoCode {
                case EADDRINUSE:
                    errorMessage = "Port \(port) is already in use. Please choose a different port or ensure no other service is using this port."
                case EACCES:
                    errorMessage = "Permission denied to bind to port \(port). This port may require elevated privileges."
                case EADDRNOTAVAIL:
                    errorMessage = "The address \(host) is not available for binding."
                default:
                    errorMessage = "Failed to bind to \(host):\(port). Error: \(error.localizedDescription)"
            }
            logger.error("\(errorMessage)")
            throw TransportError.bindingFailed(errorMessage)
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

    /// Start the keep-alive timer that sends messages every 30 seconds.
    private func startKeepAliveTimer() {
        keepAliveTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        keepAliveTimer?.schedule(deadline: .now(), repeating: .seconds(30))
        keepAliveTimer?.setEventHandler { [weak self] in
            self?.sendKeepAlive()
        }
        keepAliveTimer?.resume()
        logger.trace("Started keep-alive timer")
    }

    /// Stop the keep-alive timer.
    private func stopKeepAliveTimer() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        logger.trace("Stopped keep-alive timer")
    }

    /// Send a keep-alive message to all connected SSE clients.
    private func sendKeepAlive() {
        Task { [weak self] in
            guard let self = self else { return }

            switch self.keepAliveMode {
                case .none:
                    return
                case .sse:
                    await self.sessionManager.broadcastSSE(SSEMessage(data: ": keep-alive"))
                case .ping:
                    let ping = JSONRPCMessage.request(id: self.sequenceNumber, method: "ping")
                    let encoder = JSONEncoder()
                    let data = try! encoder.encode(ping)
                    let string = String(data: data, encoding: .utf8)!
                    let message = SSEMessage(data: string)
                    await self.sessionManager.broadcastSSE(message)
                    self.sequenceNumber += 1
            }
        }
    }

    // MARK: - Request Handling
    /// Handle a JSON-RPC request and send the response through the SSE channels.
    func handleJSONRPCRequest(_ request: JSONRPCMessage, from sessionID: UUID) {
        Task {
            try await sessionManager.session(id: sessionID).work { _ in
                guard let response = await server.handleMessage(request) else {
                    // No response to send (e.g., notification)
                    return
                }

                try await send(response)
            }
        }
    }

    // MARK: - Handling SSE Connections
    /// Broadcast a named event to all connected SSE clients.
    func broadcastSSE(_ message: SSEMessage) {
        Task {
            await sessionManager.broadcastSSE(message)
        }
    }

    /// Register a new SSE channel.
    func registerSSEChannel(_ channel: Channel, id: UUID) {
        Task {
            await sessionManager.register(channel: channel, id: id)
            let count = await sessionManager.channelCount
            logger.info("New SSE channel registered (total: \(count))")
        }

        channel.closeFuture.whenComplete { [weak self] _ in
            guard let self = self else { return }
            Task {
                let removed = await self.sessionManager.removeChannel(id: id)
                if removed {
                    let count = await self.sessionManager.channelCount
                    self.logger.info("SSE channel removed (remaining: \(count))")
                }
            }
        }
    }

    /// Send a message to a specific client.
    func sendSSE(_ message: SSEMessage, to sessionID: UUID) {
        Task {
            let session = await sessionManager.session(id: sessionID)
            session.sendSSE(message)
        }
    }


    // MARK: - Transport

    /// Send raw data to the client associated with the current `Session`.
    public func send(_ data: Data) async throws {
        precondition(Session.current != nil, "Attempted to send without an active session")
        let session = Session.current!

        let string = String(data: data, encoding: .utf8) ?? ""
        let message = SSEMessage(data: string)
        session.sendSSE(message)
    }
}
