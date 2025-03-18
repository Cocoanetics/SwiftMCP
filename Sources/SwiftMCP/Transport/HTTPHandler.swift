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
    private var clientId: String?
    
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
                } else if head.uri.hasPrefix("/messages") {
                    handleMessages(context: context, head: head, body: nil)
                } else if head.uri == "/.well-known/ai-plugin.json" {
                    handleAIPluginManifest(context: context, head: head)
                } else if head.uri == "/openapi.json" {
                    handleOpenAPISpec(context: context, head: head)
                } else {
                    // Check if this is a tool endpoint
                    let toolPath = "/\(transport.server.serverName.lowercased())"
                    if head.uri.hasPrefix(toolPath) {
                        let toolName = String(head.uri.dropFirst(toolPath.count + 1)) // +1 for the trailing slash
                        handleToolCall(context: context, head: head, toolName: toolName, body: nil)
                    } else {
                        sendResponse(context: context, status: .notFound)
                    }
                }
                
            case .body(let head, let buffer):
                if head.uri.hasPrefix("/sse") {
                    handleSSE(context: context, head: head, body: buffer)
                } else if head.uri.hasPrefix("/messages") {
                    handleMessages(context: context, head: head, body: buffer)
                } else if head.uri == "/.well-known/ai-plugin.json" {
                    handleAIPluginManifest(context: context, head: head)
                } else if head.uri == "/openapi.json" {
                    handleOpenAPISpec(context: context, head: head)
                } else {
                    // Check if this is a tool endpoint
                    let toolPath = "/" + transport.server.serverName.asModelName
                    if head.uri.hasPrefix(toolPath) {
                        let toolName = String(head.uri.dropFirst(toolPath.count + 1)) // +1 for the trailing slash
                        handleToolCall(context: context, head: head, toolName: toolName, body: buffer)
                    } else {
                        sendResponse(context: context, status: .notFound)
                    }
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
		
		guard "text/event-stream".matchesAcceptHeader(acceptHeader) else {
            transport.logger.warning("Rejected non-SSE request (Accept: \(acceptHeader))")
            sendResponse(context: context, status: .badRequest)
            return
        }
        
        let remoteAddress = context.channel.remoteAddress?.description ?? "unknown"
        let userAgent = head.headers["user-agent"].first ?? "unknown"
        
        // Generate client ID
        let clientId = UUID().uuidString
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
        
        // Register the channel with client ID first
        transport.registerSSEChannel(context.channel, id: id, clientId: clientId)
        
        // Then send endpoint event with client ID in URL
        var components = URLComponents()
        
        // Use forwarded headers if present, otherwise use transport defaults
        if let forwardedHost = head.headers["X-Forwarded-Host"].first {
            components.host = forwardedHost
        } else {
            components.host = transport.host
        }
        
        if let forwardedProto = head.headers["X-Forwarded-Proto"].first {
            components.scheme = forwardedProto
        } else {
            components.scheme = "http"
        }
        
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
            headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type, Authorization")
            
            sendResponse(context: context, status: .ok, headers: headers)
            return
        }
        
        guard head.method == .POST else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }
        
        // Extract client ID from URL path using URLComponents
        guard let components = URLComponents(string: head.uri),
              let clientId = components.path.components(separatedBy: "/").last,
              components.path.hasPrefix("/messages/") else {
            transport.logger.warning("Invalid message endpoint URL format: \(head.uri)")
            sendResponse(context: context, status: .badRequest)
            return
        }
        
		// Check authorization if handler is set
		var token: String?
		
		// First try to get token from Authorization header
		if let authHeader = head.headers["Authorization"].first {
			let parts = authHeader.split(separator: " ")
			if parts.count == 2 && parts[0].lowercased() == "bearer" {
				token = String(parts[1])
			}
		}
		
		// Validate token
		switch transport.authorizationHandler(token) {
			case .authorized:
				break // Continue with request processing
			case .unauthorized(let message):
				// Create JSON-RPC error response
				let errorResponse = """
					{
						"jsonrpc": "2.0",
						"error": {
							"code": -32001,
							"message": "Unauthorized: \(message)"
						},
						"id": null
					}
					"""
				
				// Send error via SSE
				let sseMessage = SSEMessage(data: errorResponse)
				transport.sendSSE(sseMessage, to: clientId)
				
				// Send HTTP response
				var headers = HTTPHeaders()
				headers.add(name: "Access-Control-Allow-Origin", value: "*")
				headers.add(name: "Content-Type", value: "application/json")
				sendResponse(context: context, status: .unauthorized, headers: headers)
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
            
            if request.method == nil {
                sendResponse(context: context, status: .ok, headers: nil)
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
    
    private func handleAIPluginManifest(context: ChannelHandlerContext, head: HTTPRequestHead) {
        guard head.method == .GET else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }

        // Use forwarded headers if present, otherwise use transport defaults
        let host: String
        let scheme: String
        
        if let forwardedHost = head.headers["X-Forwarded-Host"].first {
            host = forwardedHost
        } else {
            host = transport.host
        }
        
        if let forwardedProto = head.headers["X-Forwarded-Proto"].first {
            scheme = forwardedProto
        } else {
            scheme = "http"
        }

		let description = transport.server.description ?? "MCP Server providing tools for automation and integration"
		
		let manifest = AIPluginManifest(
            nameForHuman: transport.server.serverName,
            nameForModel: transport.server.serverName.asModelName,
            descriptionForHuman: description,
            descriptionForModel: description,
            auth: .none, 
            api: .init(type: "openapi", url: "\(scheme)://\(host)/openapi.json")
        )

        // Convert manifest to JSON data
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let jsonData = try encoder.encode(manifest)
            var buffer = context.channel.allocator.buffer(capacity: jsonData.count)
            buffer.writeBytes(jsonData)
            
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            
            sendResponse(context: context, status: .ok, headers: headers, body: buffer)
        } catch {
            transport.logger.error("Failed to encode AI plugin manifest: \(error)")
            sendResponse(context: context, status: .internalServerError)
        }
    }
    
    private func handleOpenAPISpec(context: ChannelHandlerContext, head: HTTPRequestHead) {
        guard head.method == .GET else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }

        // Use forwarded headers if present, otherwise use transport defaults
        let host: String
        let scheme: String
        
        if let forwardedHost = head.headers["X-Forwarded-Host"].first {
            host = forwardedHost
        } else {
            host = transport.host
        }
        
        if let forwardedProto = head.headers["X-Forwarded-Proto"].first {
            scheme = forwardedProto
        } else {
            scheme = "http"
        }

		let spec = OpenAPISpec(server: transport.server,
							   scheme: scheme,
							   host: host)
        
        // Convert spec to JSON data
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        do {
            let jsonData = try encoder.encode(spec)
            var buffer = context.channel.allocator.buffer(capacity: jsonData.count)
            buffer.writeBytes(jsonData)
            
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            
            sendResponse(context: context, status: .ok, headers: headers, body: buffer)
        } catch {
            transport.logger.error("Failed to encode OpenAPI spec: \(error)")
            sendResponse(context: context, status: .internalServerError)
        }
    }
    
    private func handleToolCall(context: ChannelHandlerContext, head: HTTPRequestHead, toolName: String, body: ByteBuffer?) {
        // Handle CORS preflight
        if head.method == .OPTIONS {
            var headers = HTTPHeaders()
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            headers.add(name: "Access-Control-Allow-Methods", value: "POST, OPTIONS")
            headers.add(name: "Access-Control-Allow-Headers", value: "*")
            headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type, Authorization")
            
            sendResponse(context: context, status: .ok, headers: headers)
            return
        }
        
        // Only allow POST method
        guard head.method == .POST else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }
        
        // Verify tool exists
        guard let tool = transport.server.mcpTools.first(where: { $0.name == toolName }) else {
            sendResponse(context: context, status: .notFound)
            return
        }
        
        // Must have a body
        guard let body = body else {
            sendResponse(context: context, status: .badRequest)
            return
        }
        
        do {
            // Get Data from ByteBuffer
            let bodyData = Data(buffer: body)
            
            // Parse request body as JSON dictionary
            guard let arguments = try JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else
			{
				throw MCPToolError.callFailed(name: "Error calling tool \(tool.name)", reason: "Arguments must be a JSON dictionary")
			}
            
            // Call the tool
            let result = try transport.server.callTool(toolName, arguments: arguments)
            
            // Convert result to JSON data
            let jsonData = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
            
            var buffer = context.channel.allocator.buffer(capacity: jsonData.count)
            buffer.writeBytes(jsonData)
            
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            
            sendResponse(context: context, status: .ok, headers: headers, body: buffer)
            
        } catch {
            transport.logger.error("Tool call error: \(error)")
            
            // Create error response
            let errorResponse = """
            {
                "error": "\(error.localizedDescription)"
            }
            """
            var buffer = context.channel.allocator.buffer(capacity: errorResponse.utf8.count)
            buffer.writeString(errorResponse)
            
            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            
            sendResponse(context: context, status: .badRequest, headers: headers, body: buffer)
        }
    }
} 
