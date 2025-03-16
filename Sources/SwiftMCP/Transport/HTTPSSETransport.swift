import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOFoundationCompat

/// A transport that exposes an HTTP server with SSE and JSON-RPC endpoints
public final class HTTPSSETransport {
    private let server: MCPServer
    private let host: String
    private let port: Int
    private let group: EventLoopGroup
    private let channel: Channel?
    private let lock = NSLock()
    private var sseChannels: [ObjectIdentifier: Channel] = [:]
    
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
        self.channel = nil
    }
    
    /// Start the HTTP server
    public func start() throws {
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.configureHTTPServerPipeline().flatMap {
                    channel.pipeline.addHandler(HTTPHandler(transport: self))
                }
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.allowRemoteHalfClosure, value: true)
        
        do {
            let channel = try bootstrap.bind(host: host, port: port).wait()
            print("Server started and listening on \(host):\(port)")
            try channel.closeFuture.wait()
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
        lock.lock()
        defer { lock.unlock() }
        
        let data = "data: \(event)\n\n"
        let buffer = channel?.allocator.buffer(string: data)
        
        for channel in sseChannels.values {
            _ = channel.writeAndFlush(HTTPServerResponsePart.body(.byteBuffer(buffer!)))
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
        
        init(transport: HTTPSSETransport) {
            self.transport = transport
        }
        
        func channelRead(context: ChannelHandlerContext, data: NIOAny) {
            let reqPart = unwrapInboundIn(data)
            
            switch reqPart {
            case .head(let head):
                requestState = .head(head)
                
            case .body(var buffer):
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
            switch head.uri {
            case "/sse":
                handleSSE(context: context, head: head)
            case "/messages":
                handleJSONRPC(context: context, head: head, body: body)
            default:
                sendNotFound(context: context)
            }
        }
        
        private func handleSSE(context: ChannelHandlerContext, head: HTTPRequestHead) {
            // Only accept GET requests for SSE
            guard head.method == .GET else {
                sendMethodNotAllowed(context: context)
                return
            }
            
            // Set up SSE headers
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "text/event-stream")
            headers.add(name: "Cache-Control", value: "no-cache")
            headers.add(name: "Connection", value: "keep-alive")
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            
            // Send headers
            let response = HTTPResponseHead(version: head.version,
                                         status: .ok,
                                         headers: headers)
            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.flush()
            
            // Add channel to SSE channels
            transport.addSSEChannel(context.channel)
            
            // Remove channel when closed
            context.channel.closeFuture.whenComplete { _ in
                self.transport.removeSSEChannel(context.channel)
            }
        }
        
        private func handleJSONRPC(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
            // Only accept POST requests for JSON-RPC
            guard head.method == .POST else {
                sendMethodNotAllowed(context: context)
                return
            }
            
            // Ensure we have a body
            guard let body = body else {
                sendBadRequest(context: context, message: "Missing request body")
                return
            }
            
            // Parse JSON-RPC request
            do {
                let decoder = JSONDecoder()
                let request = try decoder.decode(JSONRPCRequest.self, from: body)
                
                // Handle request
                let response = transport.server.handleRequest(request)
                
                // Send response
                var headers = HTTPHeaders()
                headers.add(name: "Content-Type", value: "application/json")
                headers.add(name: "Access-Control-Allow-Origin", value: "*")
                
                let responseHead = HTTPResponseHead(version: head.version,
                                                  status: .ok,
                                                  headers: headers)
                
                context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
                
                if let response = response {
                    let encoder = JSONEncoder()
                    let jsonData = try encoder.encode(response)
                    var buffer = context.channel.allocator.buffer(capacity: jsonData.count)
                    buffer.writeBytes(jsonData)
                    context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
                }
                
                context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
            } catch {
                sendBadRequest(context: context, message: "Invalid JSON-RPC request: \(error)")
            }
        }
        
        private func sendNotFound(context: ChannelHandlerContext) {
            let response = HTTPResponseHead(version: .http1_1,
                                         status: .notFound)
            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(string: "404 Not Found")))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
        
        private func sendMethodNotAllowed(context: ChannelHandlerContext) {
            let response = HTTPResponseHead(version: .http1_1,
                                         status: .methodNotAllowed)
            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(string: "405 Method Not Allowed")))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
        
        private func sendBadRequest(context: ChannelHandlerContext, message: String) {
            let response = HTTPResponseHead(version: .http1_1,
                                         status: .badRequest)
            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.write(wrapOutboundOut(.body(.byteBuffer(context.channel.allocator.buffer(string: message)))), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
        
        private func sendOK(context: ChannelHandlerContext) {
            let response = HTTPResponseHead(version: .http1_1,
                                         status: .ok)
            context.write(wrapOutboundOut(.head(response)), promise: nil)
            context.writeAndFlush(wrapOutboundOut(.end(nil)), promise: nil)
        }
    }
}

private enum RequestState {
    case idle
    case head(HTTPRequestHead)
    case body(head: HTTPRequestHead, data: ByteBuffer)
} 
