import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOFoundationCompat
import Logging

/// A transport that exposes an HTTP server with SSE and JSON-RPC endpoints
public final class HTTPSSETransport {
    public let server: MCPServer
    public let host: String
    public let port: Int

	private let logger = Logger(label: "com.cocoanetics.SwiftMCP.HTTPSSETransport")
	
    private let group: EventLoopGroup
    private var channel: Channel?
    private let channelManager = SSEChannelManager()
    private var keepAliveTimer: DispatchSourceTimer?
    
    /// Whether to serve OpenAPI endpoints (manifest, spec, and tool calls)
    public var serveOpenAPI: Bool = false
    
    /// Result of authorization check
    public enum AuthorizationResult {
        case authorized
        case unauthorized(String) // String is the error message
    }
    
    /// Authorization handler type
    public typealias AuthorizationHandler = (String?) -> AuthorizationResult
    
    /// authorization handler for bearer tokens, accepts all by default
    public var authorizationHandler: AuthorizationHandler = { _ in return .authorized }
    
    public enum KeepAliveMode {
        case none
        case sse
        case ping
    }
    
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
    
    // Number used as identifier for outputbound JSONRPCRequests, e.g. ping
    fileprivate var sequenceNumber = 1
    
    /// The number of active SSE channels
    var sseChannelCount: Int {
        get async { await channelManager.channelCount }
    }
    
    // MARK: - Initialization
    
    /// Initialize a new HTTP SSE transport
    /// - Parameters:
    ///   - server: The MCP server to expose
    ///   - host: The host to bind to (default: localhost)
    ///   - port: The port to bind to (default: 8080)
    public init(server: MCPServer, host: String = String.localHostname, port: Int = 8080) {
        self.server = server
        self.host = host
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    // MARK: - Server Lifecycle
    
    /// Run the HTTP server and block until stopped
    public func run() throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPLogger())
                }.flatMap {
                    channel.pipeline.addHandler(HTTPHandler(transport: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        
        do {
            self.channel = try bootstrap.bind(host: host, port: port).wait()
            logger.info("Server started and listening on \(host):\(port)")
            startKeepAliveTimer()
            
            // Set up handler for channel closure
            self.channel?.closeFuture.whenComplete { [weak self] result in
                guard let self = self else { return }
                
                switch result {
                case .success:
                    self.logger.info("Server channel closed normally")
                case .failure(let error):
                    self.logger.error("Server channel closed with error: \(error)")
                }
            }
            
            // Wait for the channel to close
            try self.channel?.closeFuture.wait()
            
        } catch {
            logger.error("Server error: \(error)")
            throw error
        }
    }
    
    /// Stop the HTTP server
    public func stop() throws {
        logger.info("Stopping server...")
        stopKeepAliveTimer()
        
        Task {
            await channelManager.stopAllChannels()
        }
        
        try group.syncShutdownGracefully()
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
        Task {
            switch keepAliveMode {
            case .none:
                return
                
            case .sse:
                await channelManager.broadcastSSE(SSEMessage(data: ": keep-alive"))
                
            case .ping:
                let ping = JSONRPCMessage(jsonrpc: "2.0", id: sequenceNumber, method: "ping")
                let encoder = JSONEncoder()
                let data = try! encoder.encode(ping)
                let string = String(data: data, encoding: .utf8)!
                let message = SSEMessage(data: string)
                await channelManager.broadcastSSE(message)
                sequenceNumber += 1
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
