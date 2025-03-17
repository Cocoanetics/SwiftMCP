import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOFoundationCompat
import Logging

/// A transport that exposes an HTTP server with SSE and JSON-RPC endpoints
public final class HTTPSSETransport {
    private let server: MCPServer
    let host: String
    public let port: Int
    private let group: EventLoopGroup
    private var channel: Channel?
    private let lock = NSLock()
    private var sseChannels: [UUID: Channel] = [:]
    let logger = Logger(label: "com.cocoanetics.SwiftMCP.Transport")
    
    /// The number of active SSE channels
    public var sseChannelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sseChannels.count
    }
    
    /// Initialize a new HTTP SSE transport
    /// - Parameters:
    ///   - server: The MCP server to expose
    ///   - host: The host to bind to (default: localhost)
    ///   - port: The port to bind to (default: 8080)
    public init(server: MCPServer, host: String = "localhost", port: Int = 8080) {
        self.server = server
        self.host = host
        self.port = port
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
    }
    
    /// Start the HTTP server
    public func start() throws {
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
            try self.channel!.closeFuture.wait()
        } catch {
            logger.error("Server error: \(error)")
            throw error
        }
    }
    
    /// Stop the HTTP server
    public func stop() throws {
        logger.info("Stopping server...")
        lock.lock()
        // Close all SSE channels
        for channel in sseChannels.values {
            channel.close(promise: nil)
        }
        sseChannels.removeAll()
        lock.unlock()
        
        try group.syncShutdownGracefully()
        logger.info("Server stopped")
    }
    
    /// Broadcast an event to all connected SSE clients
    /// - Parameter event: The event to broadcast
    public func broadcast(_ event: String) {
        logger.trace("Broadcasting event: \(event)")
        
        lock.lock()
        defer { lock.unlock() }
        
        // No channels connected
        if sseChannels.isEmpty {
            logger.warning("No SSE clients connected to receive broadcast")
            return
        }
        
        // Format as a proper SSE message
        let data = "data: \(event)\n\n"
        
        // Use one of the connected channels for the allocator if main channel isn't available
        guard let allocator = channel?.allocator ?? sseChannels.values.first?.allocator else {
            logger.error("No allocator available for broadcast")
            return
        }
        
        var buffer = allocator.buffer(capacity: data.utf8.count)
        buffer.writeString(data)
        
        for (_, channel) in sseChannels {
            guard channel.isActive else {
                continue
            }
            
            channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
            channel.flush()
        }
    }
    
    /// Broadcast a named event to all connected SSE clients
    /// - Parameters:
    ///   - name: The name of the event
    ///   - data: The data for the event
    public func broadcastEvent(name: String, data: String) {
        lock.lock()
        defer { lock.unlock() }
        
        // No channels connected
        if sseChannels.isEmpty {
            return
        }
        
        // Format as a proper SSE message with event name
        let messageText = "event: \(name)\ndata: \(data)\n\n"
        
        // Use one of the connected channels for the allocator if main channel isn't available
        guard let allocator = channel?.allocator ?? sseChannels.values.first?.allocator else {
            return
        }
        
        var buffer = allocator.buffer(capacity: messageText.utf8.count)
        buffer.writeString(messageText)
        
        for channel in sseChannels.values {
            guard channel.isActive else {
                continue
            }
            
            channel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)
            channel.flush()
        }
    }
    
    /// Handle a JSON-RPC request and send the response through the SSE channel
    /// - Parameter request: The JSON-RPC request
    /// - Returns: true if the request was handled, false otherwise
    func handleJSONRPCRequest(_ request: JSONRPCRequest) -> Bool {
        // Process the request
        guard let response = server.handleRequest(request) else {
            return false
        }
        
        // Encode and broadcast the response
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(response)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                return false
            }
            
            // Broadcast the response to all SSE clients
            broadcast(jsonString)
            return true
        } catch {
            return false
        }
    }
    
    /// Register a new SSE channel
    /// - Parameters:
    ///   - channel: The channel to register
    ///   - id: The unique identifier for this channel
    func registerSSEChannel(_ channel: Channel, id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        
        guard sseChannels[id] == nil else {
            return
        }
        
        sseChannels[id] = channel
        let channelCount = sseChannels.count
        logger.info("New SSE channel registered (total: \(channelCount))")
        
        // Set up cleanup when connection closes
        channel.closeFuture.whenComplete { [weak self] _ in
            guard let self = self else { return }
            self.removeSSEChannel(id: id)
        }
    }
    
    /// Remove an SSE channel and log the removal
    /// - Parameters:
    ///   - id: The unique identifier of the channel to remove
    /// - Returns: true if a channel was removed, false if no channel was found
    @discardableResult
    func removeSSEChannel(id: UUID) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        if sseChannels.removeValue(forKey: id) != nil {
            let channelCount = sseChannels.count
            logger.info("SSE channel removed (remaining: \(channelCount))")
            return true
        }
        
        return false
    }
}
