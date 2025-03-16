import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOFoundationCompat
import Logging

/// A transport that exposes an HTTP server with SSE and JSON-RPC endpoints
public final class HTTPSSETransport {
    private let server: MCPServer
    private let host: String
    public let port: Int
    private let group: EventLoopGroup
    private var channel: Channel?
    private let lock = NSLock()
    private var sseChannels: [ObjectIdentifier: Channel] = [:]
	
	let logger: Logger
    
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
		
		
		// Create a logger using Swift Logging
		logger = Logger(label: "com.cocoanetics.SwiftSMTPCLI.HTTP+SSE")
    }
    
    /// Start the HTTP server
    public func start() throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
					channel.pipeline.addHandler(HTTPHandler(transport: self, logger: self.logger))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        
        do {
            self.channel = try bootstrap.bind(host: host, port: port).wait()
            print("Server started and listening on \(host):\(port)")
            try self.channel!.closeFuture.wait()
        } catch {
            throw error
        }
    }
    
    /// Stop the HTTP server
    public func stop() throws {
        try group.syncShutdownGracefully()
    }
    
    /// Broadcast an event to all connected SSE clients
    /// - Parameter event: The event to broadcast
    public func broadcast(_ event: String) {
		
		logger.trace("\(event)")
		
        lock.lock()
        defer { lock.unlock() }
        
        // No channels connected
        if sseChannels.isEmpty {
            return
        }
        
        // Format as a proper SSE message
        let data = "data: \(event)\n\n"
		
		logger.trace("SSE Broadcast:\n\n\(data)")
        
        // Use one of the connected channels for the allocator if main channel isn't available
        guard let allocator = channel?.allocator ?? sseChannels.values.first?.allocator else {
            return
        }
        
        var buffer = allocator.buffer(capacity: data.utf8.count)
        buffer.writeString(data)
		
        for channel in sseChannels.values {
            _ = channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)))
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
		
		logger.trace("SSE Broadcast:\n\n\(messageText)")

        // Use one of the connected channels for the allocator if main channel isn't available
        guard let allocator = channel?.allocator ?? sseChannels.values.first?.allocator else {
            return
        }
        
        var buffer = allocator.buffer(capacity: messageText.utf8.count)
        buffer.writeString(messageText)
        
        for channel in sseChannels.values {
            _ = channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer)))
        }
    }
    
    /// Handle a JSON-RPC request and send the response through the SSE channel
    /// - Parameter request: The JSON-RPC request
    /// - Returns: true if the request was handled, false otherwise
    private func handleJSONRPCRequest(_ request: JSONRPCRequest) -> Bool {
        // Process the request
        guard let response = server.handleRequest(request) else {
            return false
        }
        
        // Encode and broadcast the response
        do {
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(response)
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                print("Error creating string from JSON data")
                return false
            }
            
            // Broadcast the response to all SSE clients
            broadcast(jsonString)
            print("JSON-RPC response sent through SSE for method: \(request.method)")
            return true
        } catch {
            print("Error encoding JSON-RPC response: \(error)")
            return false
        }
    }
    
    private func addSSEChannel(_ channel: Channel) {
        lock.lock()
        defer { lock.unlock() }
        sseChannels[ObjectIdentifier(channel)] = channel
    }
    
    private func removeSSEChannel(_ channel: Channel) {
        lock.lock()
        defer { lock.unlock() }
        sseChannels.removeValue(forKey: ObjectIdentifier(channel))
    }
    
    /// HTTP request handler
    private final class HTTPHandler: ChannelInboundHandler {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart
        
        private let transport: HTTPSSETransport
        private var requestState: RequestState = .idle
        
		let logger: Logger
		
		init(transport: HTTPSSETransport, logger: Logger) {
            self.transport = transport
			self.logger = logger
        }
        
		func channelRead(context: ChannelHandlerContext, data: NIOAny) {
			let reqPart = unwrapInboundIn(data)
			
			switch reqPart {
				case .head(let head):
					requestState = .head(head)
					
				case .body(let buffer):
					switch requestState {
						case .head(let head):
							requestState = .body(head: head, data: buffer)
						case .body(head: let head, data: var existingData):
							existingData.writeBytes(buffer.readableBytesView)
							requestState = .body(head: head, data: existingData)
						case .idle:
							break
					}
					
				case .end:
					switch requestState {
						case .head(let head):
							handleRequest(context: context, head: head, body: nil)
						case .body(head: let head, data: let data):
							handleRequest(context: context, head: head, body: data)
						case .idle:
							break
					}
					requestState = .idle
			}
		}
        
        private func handleRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
            // Extract path from URI (remove query string if present)
            let path = head.uri.split(separator: "?").first.map(String.init) ?? head.uri
            
            // Normal request routing
            switch path {
            case "/sse":
                handleSSE(context: context, head: head, body: body)
            case "/message":
                handleMessages(context: context, head: head, body: body)
            default:
                sendNotFound(context: context)
            }
        }
        
        private func handleSSE(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
            // Only accept GET requests for SSE
            guard head.method == .GET else {
                sendMethodNotAllowed(context: context)
                return
            }
            
            // Set up SSE headers
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "text/event-stream")
            headers.add(name: "Cache-Control", value: "no-cache, no-transform")
            headers.add(name: "Connection", value: "keep-alive")
            headers.add(name: "X-Accel-Buffering", value: "no") // Disable proxy buffering
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            headers.add(name: "Access-Control-Allow-Methods", value: "GET")
            headers.add(name: "Access-Control-Allow-Headers", value: "Cache-Control, Accept, Content-Type")
            
            // Send headers
            let response = HTTPResponseHead(version: head.version,
                                         status: .ok,
                                         headers: headers)
            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.flush()
            
            // Send endpoint event
            let endpointUrl = "http://\(transport.host):\(transport.port)/message"
            let initialData = "event: endpoint\ndata: \(endpointUrl)\n\n"

            var buffer = context.channel.allocator.buffer(capacity: initialData.utf8.count)
            buffer.writeString(initialData)
            
            context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
            context.flush()
            
            // Add channel to SSE channels
            transport.addSSEChannel(context.channel)
            
            // Remove channel when closed
            context.channel.closeFuture.whenComplete { [weak self] _ in
                guard let self = self else { return }
                self.transport.removeSSEChannel(context.channel)
            }
        }
        
        private func handleMessages(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
            // Handle CORS preflight requests
            if head.method == .OPTIONS {
                var headers = HTTPHeaders()
                headers.add(name: "Access-Control-Allow-Origin", value: "*")
                headers.add(name: "Access-Control-Allow-Methods", value: "POST, OPTIONS")
                headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type, Accept")
                headers.add(name: "Access-Control-Max-Age", value: "86400") // 24 hours
                
                let response = HTTPResponseHead(version: head.version,
                                             status: .ok,
                                             headers: headers)
                context.write(wrapOutboundOut(.head(response)), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
                return
            }
            
            // Only accept POST requests for messages
            guard head.method == .POST else {
                sendMethodNotAllowed(context: context)
                return
            }
            
            // Ensure we have a body
            guard let body = body else {
                sendBadRequest(context: context, message: "Missing request body")
                return
            }
            
            // Log body info
            print("Request body size: \(body.readableBytes) bytes")
            
            // Parse JSON-RPC request
            do {
                let decoder = JSONDecoder()
                let request = try decoder.decode(JSONRPCRequest.self, from: body)
                
                // Log the request method
                let methodName = request.method
                let requestId = request.id.map(String.init) ?? "none"
                print("Processing JSON-RPC request: method=\(methodName), id=\(requestId)")
                
                if transport.sseChannelCount == 0 {
                    print("WARNING: No active SSE connections to send response to!")
                }
                
                // Handle the request and send response through SSE
                let handled = transport.handleJSONRPCRequest(request)
                
                // Always return 202 Accepted
                var headers = HTTPHeaders()
                headers.add(name: "Content-Type", value: "application/json")
                headers.add(name: "Access-Control-Allow-Origin", value: "*")
                
                let status: HTTPResponseStatus = handled ? .accepted : .noContent
                let responseHead = HTTPResponseHead(version: head.version,
                                                  status: status,
                                                  headers: headers)
				
				logger.trace("HTTP Response: \(responseHead.description)")
                
                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            } catch {
                let errorMsg = "Invalid JSON-RPC request: \(error)"
                sendBadRequest(context: context, message: errorMsg)
            }
        }
        
        private func sendNotFound(context: ChannelHandlerContext) {
            let response = HTTPResponseHead(version: .http1_1,
                                         status: .notFound)
			logger.trace("HTTP Error: \(response.description)")
			
            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(string: "404 Not Found")))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
        
        private func sendMethodNotAllowed(context: ChannelHandlerContext) {
            let response = HTTPResponseHead(version: .http1_1,
                                         status: .methodNotAllowed)
			
			logger.trace("HTTP Error: \(response.description)")

            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(string: "405 Method Not Allowed")))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
        
        private func sendBadRequest(context: ChannelHandlerContext, message: String) {
            let response = HTTPResponseHead(version: .http1_1,
                                         status: .badRequest)
			
			logger.trace("HTTP Error: \(response.description)")
			
            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(string: message)))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

private enum RequestState {
    case idle
    case head(HTTPRequestHead)
    case body(head: HTTPRequestHead, data: ByteBuffer)
} 
