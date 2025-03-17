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
    private var clientToChannelMap: [String: UUID] = [:] // Map client IDs to channel IDs
    let logger = Logger(label: "com.cocoanetics.SwiftMCP.Transport")
    private var keepAliveTimer: DispatchSourceTimer?
	
	public enum KeepAliveMode
	{
		case none
		case sse
		case ping
	}
	
	public var keepAliveMode: KeepAliveMode = .ping
	{
		didSet {
			if oldValue != keepAliveMode {
				
				if keepAliveMode == .none {
					stopKeepAliveTimer()
				}
				else
				{
					startKeepAliveTimer()
				}
			}
		}
	}
	
	// Number used as identifier for outputbound JSONRPCRequests, e.g. ping
	fileprivate var sequenceNumber = 1
    
    /// The number of active SSE channels
    var sseChannelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return sseChannels.count
    }
	
	// MARK: - Initialization
    
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
    
	// MARK: - Server Lifecycle
	
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
            startKeepAliveTimer()
            
            // Create a semaphore that we'll never signal to keep the server running
            let semaphore = DispatchSemaphore(value: 0)
            
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
            
            // Wait forever
            semaphore.wait()
            
        } catch {
            logger.error("Server error: \(error)")
            throw error
        }
    }
    
    /// Stop the HTTP server
    public func stop() throws {
        logger.info("Stopping server...")
        stopKeepAliveTimer()
        
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
        lock.lock()
        defer { lock.unlock() }
		
		switch keepAliveMode {
			case .none:
				return
				
			case .sse:
				for channel in sseChannels.values
				{
					channel.sendSSE(": keep-alive")
				}

			case .ping:
				
				let ping = JSONRPCRequest(jsonrpc: "2.0", id: sequenceNumber, method: "ping")
				let encoder = JSONEncoder()
				let data = try! encoder.encode(ping)
				let string = String(data: data, encoding: .utf8)!
				
				let message = SSEMessage(data: string)

				for channel in sseChannels.values
				{
					channel.sendSSE(message)
				}
				
				sequenceNumber += 1
		}
    }
    
	// MARK: - Request Handling
	/// Handle a JSON-RPC request and send the response through the SSE channels
	/// - Parameter request: The JSON-RPC request
	func handleJSONRPCRequest(_ request: JSONRPCRequest, from clientId: String) {
		// Let the server process the request
		guard let response = server.handleRequest(request) else {
			// If no response is needed (e.g. for notifications), just return
			return
		}

		do
		{
			// Encode the response
			let encoder = JSONEncoder()
			let jsonData = try encoder.encode(response)
			
			guard let jsonString = String(data: jsonData, encoding: .utf8) else
			{
				// should never happen!
				logger.critical("Cannot convert JSON data to string")

				return
			}
			
			// Send the response only to the client that made the request
			lock.lock()
			defer { lock.unlock() }
			
			if let channelId = clientToChannelMap[clientId],
			   let channel = sseChannels[channelId],
			   channel.isActive {
				let message = SSEMessage(data: jsonString)
				channel.sendSSE(message)
			} else {
				logger.warning("Could not find active channel for client \(clientId)")
			}
		}
		catch
		{
			logger.critical("\(error.localizedDescription)")
		}
	}
	
	// MARK: - Handling SSE Connections
    /// Broadcast a named event to all connected SSE clients
    /// - Parameters:
    ///   - name: The name of the event
    ///   - data: The data for the event
	func broadcastSSE(_ message: SSEMessage) {
        lock.lock()
        defer { lock.unlock() }
        
        for channel in sseChannels.values {
			
			channel.sendSSE(message)
        }
    }
    
    /// Register a new SSE channel
    /// - Parameters:
    ///   - channel: The channel to register
    ///   - id: The unique identifier for this channel
    ///   - clientId: The client identifier from the request
    func registerSSEChannel(_ channel: Channel, id: UUID, clientId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        guard sseChannels[id] == nil else {
            return
        }
        
        sseChannels[id] = channel
        clientToChannelMap[clientId] = id
        let channelCount = sseChannels.count
        logger.info("New SSE channel registered for client \(clientId) (total: \(channelCount))")
        
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
            // Remove the client mapping as well
            if let clientId = clientToChannelMap.first(where: { $0.value == id })?.key {
                clientToChannelMap.removeValue(forKey: clientId)
            }
            let channelCount = sseChannels.count
            logger.info("SSE channel removed (remaining: \(channelCount))")
            return true
        }
        
        return false
    }
    
    /// Send a message to a specific client
    /// - Parameters:
    ///   - message: The SSE message to send
    ///   - clientId: The client identifier to send to
    func sendSSE(_ message: SSEMessage, to clientId: String) {
        lock.lock()
        defer { lock.unlock() }
        
        if let channelId = clientToChannelMap[clientId],
           let channel = sseChannels[channelId],
           channel.isActive {
            channel.sendSSE(message)
        }
    }
    
    /// Check if a client has an active SSE connection
    /// - Parameter clientId: The client identifier to check
    /// - Returns: true if the client has an active SSE connection
    public func hasActiveSSEConnection(for clientId: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        
        if let channelId = clientToChannelMap[clientId],
           let channel = sseChannels[channelId] {
            return channel.isActive
        }
        return false
    }
}
