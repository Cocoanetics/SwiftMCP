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
    /**
     The MCP server instance that this transport exposes.
     
     This server handles the actual business logic while the transport handles HTTP communication.
     */
    public let server: MCPServer
    
    /**
     The hostname or IP address on which the HTTP server listens.
     */
    public let host: String
    
    /**
     The port number on which the HTTP server listens.
     */
    public let port: Int
    
    /**
     Logger for logging transport events and errors.
     
     Used to track server lifecycle, connections, and error conditions.
     */
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.HTTPSSETransport")
    
    private let group: EventLoopGroup
    private var channel: Channel?
    private let channelManager = SSEChannelManager()
    private var keepAliveTimer: DispatchSourceTimer?
    
    /**
     Flag to determine whether to serve OpenAPI endpoints.
     
     When enabled, the server will expose:
     - /.well-known/ai-plugin.json
     - /openapi.json
     - Tool endpoints based on the server name
     */
    public var serveOpenAPI: Bool = false
    
    /**
     Result of an authorization check.
     
     - authorized: The request is authorized
     - unauthorized: The request is not authorized, with an error message
     */
    public enum AuthorizationResult: Sendable {
        case authorized
        case unauthorized(String)
    }
    
    /**
     A function type that handles authorization of requests.
     
     - Parameter token: The bearer token to validate, if present
     - Returns: An AuthorizationResult indicating whether the request is authorized
     */
    public typealias AuthorizationHandler = @Sendable (String?) -> AuthorizationResult
    
    /**
     Authorization handler for bearer tokens.
     
     By default, accepts all tokens (returns authorized). Can be replaced with a custom
     implementation to enforce authentication.
     */
    public var authorizationHandler: AuthorizationHandler = { _ in return .authorized }
    
    /**
     Defines the available keep-alive modes for maintaining connections.
     
     - none: No keep-alive messages are sent
     - sse: Sends SSE-specific keep-alive comments
     - ping: Sends JSON-RPC ping messages
     */
    public enum KeepAliveMode: Sendable {
        case none
        case sse
        case ping
    }
    
    /**
     The current keep-alive mode for the transport.
     
     Changes to this property will automatically start or stop the keep-alive timer
     as appropriate.
     */
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
    
    // Number used as identifier for output-bound JSONRPCRequests, e.g. ping
    fileprivate var sequenceNumber = 1
    
    /**
     The number of active SSE channels currently connected to the server.
     */
    var sseChannelCount: Int {
        get async { await channelManager.channelCount }
    }
    
    // MARK: - Initialization
    
    /**
     Initializes a new HTTP SSE transport with the specified server and network settings.
     
     - Parameters:
       - server: The MCP server to expose
       - host: The host to bind to (defaults to the local hostname)
       - port: The port to bind to (defaults to 8080)
     */
    public init(server: MCPServer, host: String = String.localHostname, port: Int = 8080) {
        self.server = server
        self.host = host
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    /**
     Convenience initializer that creates an HTTP SSE transport with default network settings.
     
     This initializer uses the local hostname and port 8080.
     
     - Parameter server: The MCP server to expose
     */
    public convenience init(server: MCPServer) {
        self.init(server: server, host: String.localHostname, port: 8080)
    }
    
    // MARK: - Server Lifecycle
    
    /**
     Starts the HTTP server in the background.
     
     This method:
     - Initializes the NIO server bootstrap
     - Configures the HTTP pipeline
     - Starts accepting connections
     - Initializes the keep-alive timer
     
     - Throws: An error if the server fails to start
     */
    public func start() async throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { [weak self] channel in
                guard let self = self else {
                    return channel.eventLoop.makeFailedFuture(CancellationError())
                }
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
            
            // Set up handler for channel closure
            self.channel?.closeFuture.whenComplete { [logger] result in
                switch result {
                case .success:
                    logger.info("Server channel closed normally")
                case .failure(let error):
                    logger.error("Server channel closed with error: \(error)")
                }
            }
        } catch {
            logger.error("Server error: \(error)")
            throw error
        }
    }
    
    /**
     Runs the HTTP server and blocks until the server is stopped.
     
     This method:
     1. Starts the server
     2. Waits for the server channel to close
     
     - Throws: An error if the server fails to start or encounters an error while running
     */
    public func run() async throws {
        try await start()
        try await channel?.closeFuture.get()
    }
    
    /**
     Stops the HTTP server.
     
     This method:
     1. Stops the keep-alive timer
     2. Closes all SSE channels
     3. Shuts down the event loop group
     
     - Throws: An error if the server fails to stop cleanly
     */
    public func stop() async throws {
        logger.info("Stopping server...")
        stopKeepAliveTimer()
        
        await channelManager.stopAllChannels()
        
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
    
    /// Start the keep-alive timer that sends messages every 5 seconds
    private func startKeepAliveTimer() {
        keepAliveTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
        keepAliveTimer?.schedule(deadline: .now(), repeating: .seconds(30))
        keepAliveTimer?.setEventHandler { [weak self] in
            self?.sendKeepAlive()
        }
        keepAliveTimer?.resume()
        logger.trace("Started keep-alive timer")
    }
    
    /// Stop the keep-alive timer
    private func stopKeepAliveTimer() {
        keepAliveTimer?.cancel()
        keepAliveTimer = nil
        logger.trace("Stopped keep-alive timer")
    }
    
    /// Send a keep-alive message to all connected SSE clients
    private func sendKeepAlive() {
        Task { [weak self] in
            guard let self = self else { return }
            
            switch self.keepAliveMode {
            case .none:
                return
                
            case .sse:
                await self.channelManager.broadcastSSE(SSEMessage(data: ": keep-alive"))
                
            case .ping:
                let ping = JSONRPCMessage(jsonrpc: "2.0", id: self.sequenceNumber, method: "ping")
                let encoder = JSONEncoder()
                let data = try! encoder.encode(ping)
                let string = String(data: data, encoding: .utf8)!
                let message = SSEMessage(data: string)
                await self.channelManager.broadcastSSE(message)
                self.sequenceNumber += 1
            }
        }
    }
    
    // MARK: - Request Handling
    /// Handle a JSON-RPC request and send the response through the SSE channels
    /// - Parameter request: The JSON-RPC request
    func handleJSONRPCRequest(_ request: JSONRPCMessage, from clientId: String) {
        Task {
            // Let the server process the request
            guard let response = await server.handleRequest(request) else {
                // If no response is needed (e.g. for notifications), just return
                return
            }
            
            do {
                // Encode the response
                let encoder = JSONEncoder()
                let jsonData = try encoder.encode(response)
                
                guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                    logger.critical("Cannot convert JSON data to string")
                    return
                }
                
                // Send the response only to the client that made the request
                await channelManager.sendSSE(SSEMessage(data: jsonString), to: clientId)
            } catch {
                logger.critical("Failed to encode response: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Handling SSE Connections
    /// Broadcast a named event to all connected SSE clients
    /// - Parameters:
    ///   - name: The name of the event
    ///   - data: The data for the event
    func broadcastSSE(_ message: SSEMessage) {
        Task {
            await channelManager.broadcastSSE(message)
        }
    }
    
    /// Register a new SSE channel
    /// - Parameters:
    ///   - channel: The channel to register
    ///   - id: The unique identifier for this channel
    func registerSSEChannel(_ channel: Channel, id: UUID) {
        Task {
            await channelManager.register(channel: channel, id: id)
            let count = await channelManager.channelCount
            logger.info("New SSE channel registered (total: \(count))")
        }
        
        // Set up cleanup when the connection closes
        channel.closeFuture.whenComplete { [weak self] _ in
            guard let self = self else { return }
            Task {
                let removed = await self.channelManager.removeChannel(id: id)
                if removed {
                    let count = await self.channelManager.channelCount
                    self.logger.info("SSE channel removed (remaining: \(count))")
                }
            }
        }
    }
    
    /// Send a message to a specific client
    /// - Parameters:
    ///   - message: The SSE message to send
    ///   - clientId: The client identifier to send to
    func sendSSE(_ message: SSEMessage, to clientId: String) {
        Task {
            await channelManager.sendSSE(message, to: clientId)
        }
    }
}
