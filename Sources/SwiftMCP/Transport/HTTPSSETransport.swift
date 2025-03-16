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
    private let logger = Logger(label: "com.cocoanetics.SwiftMCP.HTTPSSETransport")
    
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
                    channel.pipeline.addHandler(HTTPLogger(label: "com.cocoanetics.SwiftMCP.HTTP"))
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
        logger.trace("Broadcasting event: \(event)")
        
        lock.lock()
        defer { lock.unlock() }
        
        // No channels connected
        if sseChannels.isEmpty {
            return
        }
        
        // Format as a proper SSE message
        let data = "data: \(event)\n\n"
        
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
                logger.error("Error creating string from JSON data")
                return false
            }
            
            // Broadcast the response to all SSE clients
            broadcast(jsonString)
            return true
        } catch {
            logger.error("Error encoding JSON-RPC response: \(error)")
            return false
        }
    }
    
    private func addSSEChannel(_ channel: Channel) {
        lock.lock()
        defer { lock.unlock() }
        sseChannels[ObjectIdentifier(channel)] = channel
        logger.trace("SSE: Client connected")
    }
    
    private func removeSSEChannel(_ channel: Channel) {
        lock.lock()
        defer { lock.unlock() }
        sseChannels.removeValue(forKey: ObjectIdentifier(channel))
        logger.trace("SSE: Client disconnected")
    }
    
    /// HTTP request handler
    private final class HTTPHandler: ChannelInboundHandler {
        typealias InboundIn = HTTPServerRequestPart
        typealias OutboundOut = HTTPServerResponsePart
        
        private var requestState: RequestState = .idle
        private let transport: HTTPSSETransport
        
        init(transport: HTTPSSETransport) {
            self.transport = transport
        }
        
        private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, headers: HTTPHeaders? = nil, body: ByteBuffer? = nil) {
            var responseHeaders = headers ?? HTTPHeaders()
            if body != nil {
                responseHeaders.add(name: "Content-Type", value: "application/json")
            }
            
            let head = HTTPResponseHead(version: .http1_1, status: status, headers: responseHeaders)
            context.write(self.wrapOutboundOut(.head(head)), promise: nil)
            
            if let body = body {
                context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
            }
            
            context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
            context.flush()
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
                default:
                    break
                }
                
            case .end:
                switch requestState {
                case .head(let head):
                    if head.uri.hasPrefix("/sse") {
                        handleSSE(context: context, head: head, body: nil)
                    } else if head.uri.hasPrefix("/message") {
                        handleMessages(context: context, head: head, body: nil)
                    } else {
                        sendResponse(context: context, status: .notFound)
                    }
                    
                case .body(let head, let buffer):
                    if head.uri.hasPrefix("/sse") {
                        handleSSE(context: context, head: head, body: buffer)
                    } else if head.uri.hasPrefix("/message") {
                        handleMessages(context: context, head: head, body: buffer)
                    } else {
                        sendResponse(context: context, status: .notFound)
                    }
                    
                case .idle:
                    break
                }
                requestState = .idle
            }
        }
        
        func channelReadComplete(context: ChannelHandlerContext) {
            context.flush()
        }
        
        func errorCaught(context: ChannelHandlerContext, error: Error) {
            transport.logger.error("Channel error: \(error)")
            context.close(promise: nil)
        }
        
        private func handleSSE(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
            guard head.method == .GET else {
                sendResponse(context: context, status: .methodNotAllowed)
                return
            }
            
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "text/event-stream")
            headers.add(name: "Cache-Control", value: "no-cache")
            headers.add(name: "Connection", value: "keep-alive")
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            headers.add(name: "Access-Control-Allow-Methods", value: "GET")
            headers.add(name: "Access-Control-Allow-Headers", value: "*")
            
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
            
            transport.addSSEChannel(context.channel)
            
            context.channel.closeFuture.whenComplete { [weak self] _ in
                guard let self = self else { return }
                self.transport.removeSSEChannel(context.channel)
            }
        }
        
        private func handleMessages(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
            if head.method == .OPTIONS {
                var headers = HTTPHeaders()
                headers.add(name: "Access-Control-Allow-Origin", value: "*")
                headers.add(name: "Access-Control-Allow-Methods", value: "POST, OPTIONS")
                headers.add(name: "Access-Control-Allow-Headers", value: "*")
                
                sendResponse(context: context, status: .ok, headers: headers)
                return
            }
            
            guard head.method == .POST else {
                sendResponse(context: context, status: .methodNotAllowed)
                return
            }
            
            guard let body = body else {
                sendResponse(context: context, status: .badRequest)
                return
            }
            
            let decoder = JSONDecoder()
            do {
                let request = try decoder.decode(JSONRPCRequest.self, from: body)
                let handled = transport.handleJSONRPCRequest(request)
                
                var headers = HTTPHeaders()
                headers.add(name: "Access-Control-Allow-Origin", value: "*")
                headers.add(name: "Content-Type", value: "application/json")
                
                sendResponse(context: context, status: .accepted, headers: headers)
            } catch {
                transport.logger.error("Failed to decode JSON-RPC request: \(error)")
                sendResponse(context: context, status: .badRequest)
            }
        }
    }
}

private enum RequestState {
    case idle
    case head(HTTPRequestHead)
    case body(head: HTTPRequestHead, data: ByteBuffer)
} 
