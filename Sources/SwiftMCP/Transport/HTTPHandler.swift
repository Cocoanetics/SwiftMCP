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
	
	private let logger = Logger(label: "com.cocoanetics.SwiftMCP.HTTPHandler")
    
	// MARK: - Initialization
	
    init(transport: HTTPSSETransport) {
        self.transport = transport
    }
	
	// MARK: - Channel Handler
    
    func channelInactive(context: ChannelHandlerContext) {
        logger.trace("Channel inactive")
        context.fireChannelInactive()
    }
    
    func errorCaught(context: ChannelHandlerContext, error: Error) {
        logger.error("Channel error: \(error)")
        context.close(promise: nil)
    }
    
	func channelRead(context: ChannelHandlerContext, data: NIOAny) {
		
		let requestPart = unwrapInboundIn(data)
		
		switch (requestPart, requestState) {
				
			// Initial HEAD Received
			case (.head(let head), _):
				requestState = .head(head)
				
			// BODY Received after HEAD
			case (.body(let buffer), .head(let head)):
				requestState = .body(head: head, data: buffer)
				
			// BODY Received in an unexpected state
			case (.body, _):
				logger.warning("Received unexpected body without a valid head")
				
			// END Received without prior state
			case (.end, .idle):
				logger.warning("Received end without prior request state")
				
			// END Received after HEAD (no body)
			case (.end, .head(let head)):
				defer { requestState = .idle }
				handleRequest(context: context, head: head, body: nil)
				
			// END Received after BODY
			case (.end, .body(let head, let buffer)):
				defer { requestState = .idle }
				handleRequest(context: context, head: head, body: buffer)
		}
	}
	
	private func handleRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
		
		let method = head.method
		let uri = head.uri
		let toolPath = "/\(transport.server.serverName.asModelName)"
		
		switch (method, uri) {
				
			// SSE Endpoint
			case (.GET, let path) where path.hasPrefix("/sse"):
				handleSSE(context: context, head: head, body: body)
				
			// Messages POST
			case (.POST, let path) where path.hasPrefix("/messages"):
				Task {
					await handleMessages(context: context, head: head, body: body)
				}
				
			// Messages OPTIONS (CORS Preflight)
			case (.OPTIONS, let path) where path.hasPrefix("/messages"):
				handleOPTIONS(context: context, head: head)
				
			// AI Plugin Manifest (OpenAPI)
			case (.GET, "/.well-known/ai-plugin.json"):
				handleAIPluginManifest(context: context, head: head)
				
			// OpenAPI Spec
			case (.GET, "/openapi.json"):
				handleOpenAPISpec(context: context, head: head)
				
			// Tool Endpoint POST
			case (.POST, let path) where path.hasPrefix(toolPath):
				handleToolCall(context: context, head: head, body: body)
				
			// Tool Endpoint OPTIONS (CORS Preflight)
			case (.OPTIONS, let path) where path.hasPrefix(toolPath):
				handleOPTIONS(context: context, head: head)
				
			// OPTIONS General Fallback (CORS Preflight)
			case (.OPTIONS, _):
				handleOPTIONS(context: context, head: head)
				
			// MARK: - Fallback Not Found
			default:
				sendResponse(context: context, status: .notFound)
		}
	}
	
    func channelReadComplete(context: ChannelHandlerContext) {
        context.flush()
    }
    
    private func handleSSE(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
        guard head.method == .GET else {
            logger.warning("Rejected non-GET SSE request")
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }
        
        // Validate SSE headers
        let acceptHeader = head.headers["accept"].first ?? ""
        
        logger.info("""
            SSE connection attempt:
            - Accept: \(acceptHeader)
            - Headers: \(head.headers)
            """)
        
        guard "text/event-stream".matchesAcceptHeader(acceptHeader) else {
            logger.warning("Rejected non-SSE request (Accept: \(acceptHeader))")
            sendResponse(context: context, status: .badRequest)
            return
        }
        
        let remoteAddress = context.channel.remoteAddress?.description ?? "unknown"
        let userAgent = head.headers["user-agent"].first ?? "unknown"
        
        // Generate client ID
        let clientId = UUID().uuidString
        self.clientId = clientId
        
        logger.info("""
            SSE connection attempt:
            - Client ID: \(clientId)
            - Remote: \(remoteAddress)
            - User-Agent: \(userAgent)
            - Accept: \(acceptHeader)
            """)
        
        // Register the channel with client ID
        logger.info("Registering SSE channel for client \(clientId)")
        transport.registerSSEChannel(context.channel, id: UUID(uuidString: clientId)!)
        
        // Then send endpoint event with client ID in URL
        guard let endpointUrl = self.endpointUrl(from: head, clientId: clientId) else {
            logger.error("Failed to construct endpoint URL")
            context.close(promise: nil)
            return
        }
        
        // Set up SSE response headers
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/event-stream")
        headers.add(name: "Cache-Control", value: "no-cache")
        headers.add(name: "Connection", value: "keep-alive")
        headers.add(name: "Access-Control-Allow-Methods", value: "GET")
        headers.add(name: "Access-Control-Allow-Headers", value: "*")
        
        let response = HTTPResponseHead(version: head.version,
                                     status: .ok,
                                     headers: headers)
        
        logger.info("Sending SSE response headers")
        context.write(wrapOutboundOut(.head(response)), promise: nil)
        context.flush()
        
        logger.info("Sending endpoint event with URL: \(endpointUrl)")
        let message = SSEMessage(name: "endpoint", data: endpointUrl.absoluteString)
        context.channel.sendSSE(message)
        
        logger.info("SSE connection setup complete for client \(clientId)")
    }
    
	private func handleMessages(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) async {
        
        guard head.method == .POST else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }
        
        // Extract client ID from URL path using URLComponents
        guard let components = URLComponents(string: head.uri),
              let clientId = components.path.components(separatedBy: "/").last,
              components.path.hasPrefix("/messages/") else {
            logger.warning("Invalid message endpoint URL format: \(head.uri)")
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
        if case .unauthorized(let message) = transport.authorizationHandler(token) {
            let errorMessage = JSONRPCMessage(error: .init(code: 401, message: "Unauthorized: \(message)"))
            
            let data = try! JSONEncoder().encode(errorMessage)
            let errorResponse = String(data: data, encoding: .utf8)!
            
            // Send error via SSE
            let sseMessage = SSEMessage(data: errorResponse)
            transport.sendSSE(sseMessage, to: clientId)
        }
        
        guard let body = body else {
            sendResponse(context: context, status: .badRequest)
            return
        }
        
        let decoder = JSONDecoder()
        do {
            let request = try decoder.decode(JSONRPCMessage.self, from: body)
            
            if request.method == nil {
                sendResponse(context: context, status: .ok, headers: nil)
                return
            }
            
            // Send Accepted first
            sendResponse(context: context, status: .accepted)
            
            // Handle the response with client ID
            transport.handleJSONRPCRequest(request, from: clientId)
            
        } catch {
            sendResponse(context: context, status: .badRequest)
        }
    }
	
	// MARK: - OpenAPI Handlers
    
    private func handleAIPluginManifest(context: ChannelHandlerContext, head: HTTPRequestHead) {
		
        guard head.method == .GET else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }
		
		guard transport.serveOpenAPI else {
			sendResponse(context: context, status: .notFound)
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
            
            sendResponse(context: context, status: .ok, body: buffer)
        } catch {
            logger.error("Failed to encode AI plugin manifest: \(error)")
            sendResponse(context: context, status: .internalServerError)
        }
    }
    
    private func handleOpenAPISpec(context: ChannelHandlerContext, head: HTTPRequestHead) {
		
        guard head.method == .GET else {
            sendResponse(context: context, status: .methodNotAllowed)
            return
        }
		
		guard transport.serveOpenAPI else {
			sendResponse(context: context, status: .notFound)
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
            
            sendResponse(context: context, status: .ok, body: buffer)
        } catch {
            logger.error("Failed to encode OpenAPI spec: \(error)")
            sendResponse(context: context, status: .internalServerError)
        }
    }
    
	private func handleToolCall(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {

		// Only allow POST method
		guard head.method == .POST else {
			sendResponse(context: context, status: .methodNotAllowed)
			return
		}

		guard transport.serveOpenAPI else {
			sendResponse(context: context, status: .notFound)
			return
		}

		// Split the URI into components and validate the necessary parts
		let pathComponents = head.uri.split(separator: "/").map(String.init)

		guard
			pathComponents.count == 2,
			let serverComponent = pathComponents.first,
			let toolName = pathComponents.dropFirst().first,
			serverComponent == transport.server.serverName.asModelName
		else {
			sendResponse(context: context, status: .notFound)
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
        if case .unauthorized(let message) = transport.authorizationHandler(token) {
            let errorDict = ["error": "Unauthorized: \(message)"] as [String: String]
            let data = try! JSONEncoder().encode(errorDict)
            var buffer = context.channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            
             sendResponse(context: context, status: .unauthorized, body: buffer)
            return
        }
        
        // Must have a body
        guard let body = body else {
            sendResponse(context: context, status: .badRequest)
            return
        }
        

		// Get Data from ByteBuffer
		let bodyData = Data(buffer: body)
		let allocator = context.channel.allocator
		
		Task {
			
			do {
				// Parse request body as JSON dictionary
				guard let arguments = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] else
				{
					throw MCPToolError.invalidJSONDictionary
				}
				
				// Call the tool
				let result = try await transport.server.callTool(toolName, arguments: arguments)
				
				// Convert result to JSON data
				let jsonData = try JSONEncoder().encode(result)
				
				var buffer = allocator.buffer(capacity: jsonData.count)
				buffer.writeBytes(jsonData)
				
				self.sendResponse(context: context, status: .ok, body: buffer)
				
			} catch {
				let errorDict = ["error": error.localizedDescription] as [String : String]
				let data = try! JSONEncoder().encode(errorDict)
				let string = String(data: data, encoding: .utf8)!
				
				var status = HTTPResponseStatus.badRequest
				
				if let mcpError = error as? MCPToolError, case .unknownTool(_) = mcpError {
					status = .notFound
				}
				
				var buffer = allocator.buffer(capacity: string.utf8.count)
				buffer.writeString(string)
				
				self.sendResponse(context: context, status: status, body: buffer)
			}
		}
	}
	
	// MARK: - Helpers
	
	fileprivate func endpointUrl(from head: HTTPRequestHead, clientId: String) -> URL? {
		var components = URLComponents()
		
		// Get the host from the request headers or connection
		if let host = head.headers["Host"].first {
			components.host = host
		} else if let remoteAddress = head.headers["X-Forwarded-Host"].first {
			components.host = remoteAddress
		} else {
			components.host = transport.host
		}
		
		// Get the scheme from the request headers or connection
		if let proto = head.headers["X-Forwarded-Proto"].first {
			components.scheme = proto
		} else {
			components.scheme = "http"
		}
		
		// Get the port from the request headers or connection
		if let port = head.headers["X-Forwarded-Port"].first {
			components.port = Int(port)
		} else if let host = components.host, host.contains(":") {
			// Extract port from host if present
			let parts = host.split(separator: ":")
			components.host = String(parts[0])
			components.port = Int(parts[1])
		} else {
			components.port = transport.port
		}
		
		components.path = "/messages/\(clientId)"
		
		// remove port if implied by scheme
		if components.port == 80, components.scheme == "http" {
			components.port = nil
		}
		else if components.port == 443, components.scheme == "https" {
			components.port = nil
		}
		
		logger.info("Generated endpoint URL: \(components.url?.absoluteString ?? "nil")")
		return components.url
	}
    
    private func handleOPTIONS(context: ChannelHandlerContext, head: HTTPRequestHead) {
        logger.info("Handling OPTIONS request for URI: \(head.uri)")
        var headers = HTTPHeaders()
        headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
        headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type, Authorization")
        sendResponse(context: context, status: .ok, headers: headers)
    }
	
	private func sendResponse(context: ChannelHandlerContext, status: HTTPResponseStatus, headers: HTTPHeaders? = nil, body: ByteBuffer? = nil) {
		
		context.eventLoop.execute {
			
			var responseHeaders = headers ?? HTTPHeaders()
			
			if body != nil {
				responseHeaders.add(name: "Content-Type", value: "application/json")
			}
			
			responseHeaders.add(name: "Access-Control-Allow-Origin", value: "*")
			
			let head = HTTPResponseHead(version: .http1_1, status: status, headers: responseHeaders)
			context.write(self.wrapOutboundOut(.head(head)), promise: nil)
			
			if let body = body {
				context.write(self.wrapOutboundOut(.body(.byteBuffer(body))), promise: nil)
			}
			
			context.write(self.wrapOutboundOut(.end(nil)), promise: nil)
			context.flush()
		}
	}
}
