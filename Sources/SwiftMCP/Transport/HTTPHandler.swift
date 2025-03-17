import Foundation
import NIOCore
import NIOHTTP1
import Logging

/// HTTP request handler for the SSE transport
final class HTTPHandler: ChannelInboundHandler, Identifiable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart
    
    private var requestState: RequestState = .idle
    private let transport: HTTPSSETransport
    let id = UUID()
    private var clientId: UUID?
    
    init(transport: HTTPSSETransport) {
        self.transport = transport
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        transport.logger.trace("Channel inactive")
        transport.removeSSEChannel(id)
        context.fireChannelInactive()
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        transport.logger.error("Channel error: \(error)")
        transport.removeSSEChannel(id)
        context.close(promise: nil)
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
                } else if head.uri.hasPrefix("/messages") {
                    handleMessages(context: context, head: head, body: nil)
                } else {
                    sendResponse(context: context, status: .notFound)
                }
                
            case .body(let head, let buffer):
                if head.uri.hasPrefix("/sse") {
                    handleSSE(context: context, head: head, body: buffer)
                } else if head.uri.hasPrefix("/messages") {
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
    
    private func handleSSE(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        guard head.method == .GET else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }
        
        // Validate SSE headers
        let acceptHeader = head.headers["accept"].first ?? ""
        guard acceptHeader.contains("text/event-stream") else {
            transport.logger.warning("Rejected non-SSE request (Accept: \(acceptHeader))")
            sendResponse(context: context, status: .badRequest)
            return
        }
        
        let remoteAddress = context.channel.remoteAddress?.description ?? "unknown"
        let userAgent = head.headers["user-agent"].first ?? "unknown"
        
        // Generate client ID
        let clientId = UUID()
        self.clientId = clientId
        
        transport.logger.info("""
            SSE connection attempt:
            - Client ID: \(clientId)
            - Remote: \(remoteAddress)
            - User-Agent: \(userAgent)
            - Accept: \(acceptHeader)
            """)
        
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
        
        // Register the channel with client ID
        transport.registerSSEChannel(context.channel, clientId: clientId)
        
        // Then send endpoint event with client ID in URL
        var components = URLComponents()
        components.scheme = "http"
        components.host = transport.host
        components.port = Int(transport.port)
        components.path = "/messages/\(clientId)"
        
        guard let endpointUrl = components.string else {
            transport.logger.error("Failed to construct endpoint URL")
            context.close(promise: nil)
            return
        }
        
        let message = SSEMessage(name: "endpoint", data: endpointUrl)
        context.channel.sendSSE(message)
    }
    
    private func handleMessages(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        if head.method == .OPTIONS {
            var headers = HTTPHeaders()
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            headers.add(name: "Access-Control-Allow-Methods", value: "POST, OPTIONS")
            headers.add(name: "Access-Control-Allow-Headers", value: "*")
            headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type")
            
            sendResponse(context: context, status: .ok, headers: headers)
            return
        }
        
        guard head.method == .POST else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }
        
        // Extract client ID from URL path using URLComponents
        guard let components = URLComponents(string: head.uri),
              let clientIdString = components.path.components(separatedBy: "/").last,
              let clientId = UUID(uuidString: clientIdString),
              components.path.hasPrefix("/messages/") else {
            transport.logger.warning("Invalid message endpoint URL format: \(head.uri)")
            sendResponse(context: context, status: .badRequest)
            return
        }
        
        guard let body = body else {
            sendResponse(context: context, status: .badRequest)
            return
        }
        
        let decoder = JSONDecoder()
        do {
            let request = try decoder.decode(JSONRPCRequest.self, from: body)
            
            // Verify that this client has an active SSE connection
            if !transport.hasActiveSSEConnection(for: clientId) {
                transport.logger.warning("Rejected POST request from client \(clientId) without active SSE connection")
                var headers = HTTPHeaders()
                headers.add(name: "Access-Control-Allow-Origin", value: "*")
                headers.add(name: "Content-Type", value: "application/json")
                
                // Create error response
                let errorResponse = """
                {
                    "jsonrpc": "2.0",
                    "error": {
                        "code": -32600,
                        "message": "No active SSE connection found for this client ID. Please establish an SSE connection first."
                    },
                    "id": \(request.id ?? 0)
                }
                """
                var buffer = context.channel.allocator.buffer(capacity: errorResponse.utf8.count)
                buffer.writeString(errorResponse)
                
                sendResponse(context: context, status: .forbidden, headers: headers, body: buffer)
                return
            }
            
            // Send Accepted first
            var headers = HTTPHeaders()
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            headers.add(name: "Content-Type", value: "application/json")
            sendResponse(context: context, status: .accepted, headers: headers)
            
            // Handle the response with client ID
            transport.handleJSONRPCRequest(request, from: clientId)
            
        } catch {
            sendResponse(context: context, status: .badRequest)
        }
    }
} 
