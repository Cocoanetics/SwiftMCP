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
    
    init(transport: HTTPSSETransport) {
        self.transport = transport
    }
    
    func channelInactive(context: ChannelHandlerContext) {
        transport.logger.trace("Channel inactive")
        transport.removeSSEChannel(id: id)
        context.fireChannelInactive()
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        transport.logger.error("Channel error: \(error)")
        transport.removeSSEChannel(id: id)
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
        
        transport.logger.info("""
            SSE connection attempt:
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
        
        // Send endpoint event
        let endpointUrl = "http://\(transport.host):\(transport.port)/message"
        let initialData = "event: endpoint\ndata: \(endpointUrl)\n\n"
        
        var buffer = context.channel.allocator.buffer(capacity: initialData.utf8.count)
        buffer.writeString(initialData)
        context.write(wrapOutboundOut(.body(.byteBuffer(buffer))), promise: nil)
        context.flush()
        
        // Register the channel
        transport.registerSSEChannel(context.channel, id: id)
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
            
			// Send Accepted first
            var headers = HTTPHeaders()
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            headers.add(name: "Content-Type", value: "application/json")
            sendResponse(context: context, status: .accepted, headers: headers)
			
			// Handle the response
			transport.handleJSONRPCRequest(request)

        } catch {
            sendResponse(context: context, status: .badRequest)
        }
    }
} 
