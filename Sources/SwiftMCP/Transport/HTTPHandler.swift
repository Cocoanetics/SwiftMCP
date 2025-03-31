import Foundation
@preconcurrency import NIOCore
import NIOHTTP1
import Logging

/// HTTP request handler for the SSE transport
final class HTTPHandler: ChannelInboundHandler, Identifiable, @unchecked Sendable {
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
	
	func channelReadComplete(context: ChannelHandlerContext) {
		context.flush()
	}
	
	// MARK: - Handler
	
	private func handleRequest(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
		
		let serverPath = "/\(transport.server.serverName.asModelName)"
		
		switch (head.method, head.uri) {
				
			// Handle all OPTIONS requests in one case
			case (.OPTIONS, _):
				handleOPTIONS(context: context, head: head)
				
			// SSE Endpoint
				
			case (.GET, let path) where path.hasPrefix("/sse"):
				handleSSE(context: context, head: head, body: body)
				
			case (_, let path) where path.hasPrefix("/sse"):
				sendResponse(context: context, status: .methodNotAllowed)
				
			// Messages
				
			case (.POST, let path) where path.hasPrefix("/messages"):
				
				// Create a channel reference that can be safely passed to the Task
				let channel = context.channel
				
				// Extract necessary information from head and body before passing to Task
				let requestHead = head
				let requestBody = body
				
				Task {
					// Use extracted values instead of context directly
					await self.handleMessagesAsync(channel: channel, head: requestHead, body: requestBody)
				}
				
			case (_, let path) where path.hasPrefix("/messages"):
				sendResponse(context: context, status: .methodNotAllowed)
				
			// if OpenAPI is disabled: everything else is NOT FOUND
				
			case (_, _) where !transport.serveOpenAPI:
				sendResponse(context: context, status: .notFound)
				
			// AI Plugin Manifest (OpenAPI)
				
			case (.GET, "/.well-known/ai-plugin.json"):
				handleAIPluginManifest(context: context, head: head)
				
			case (_, "/.well-known/ai-plugin.json"):
				sendResponse(context: context, status: .methodNotAllowed)
				
			// OpenAPI Spec
				
			case (.GET, "/openapi.json"):
				handleOpenAPISpec(context: context, head: head)
				
			case (_, "/openapi.json"):
				sendResponse(context: context, status: .methodNotAllowed)
				
			// Tool Endpoint
			case (.POST, let path) where path.hasPrefix(serverPath):
				handleToolCall(context: context, head: head, body: body)
				
			case (_, let path) where path.hasPrefix(serverPath):
				sendResponse(context: context, status: .methodNotAllowed)
				
				// Fallback for unknown endpoints
			default:
				sendResponse(context: context, status: .notFound)
		}
	}
	
	private func handleSSE(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?) {
		
		precondition(head.method == .GET)
		
		// Validate SSE headers
		let acceptHeader = head.headers["accept"].first ?? ""
		
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
	
	/// Async version of handleMessages that works with Sendable types
	private func handleMessagesAsync(channel: Channel, head: HTTPRequestHead, body: ByteBuffer?) async {
		// Extract client ID from URL path using URLComponents
		guard let components = URLComponents(string: head.uri),
			  let clientId = components.path.components(separatedBy: "/").last,
			  components.path.hasPrefix("/messages/") else {
			logger.warning("Invalid message endpoint URL format: \(head.uri)")
			await sendResponseAsync(channel: channel, status: .badRequest)
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
			let errorMessage = JSONRPCErrorResponse(error: .init(code: 401, message: "Unauthorized: \(message)"))
			
			let data = try! JSONEncoder().encode(errorMessage)
			let errorResponse = String(data: data, encoding: .utf8)!
			
			// Send error via SSE
			let sseMessage = SSEMessage(data: errorResponse)
			transport.sendSSE(sseMessage, to: clientId)
		}
		
		guard let body = body else {
			await sendResponseAsync(channel: channel, status: .badRequest)
			return
		}
		
		do {
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			let request = try decoder.decode(JSONRPCRequest.self, from: body)
			
			if request.method == nil {
				await sendResponseAsync(channel: channel, status: .ok, headers: nil)
				return
			}
			
			// Send Accepted first
			await sendResponseAsync(channel: channel, status: .accepted)
			
			// Handle the response with client ID
			transport.handleJSONRPCRequest(request, from: clientId)
			
		} catch {
			logger.error("Failed to decode JSON-RPC message: \(error)")
			await sendResponseAsync(channel: channel, status: .badRequest)
		}
	}
	
	/// Async version of sendResponse that works with Channel instead of ChannelHandlerContext
	private func sendResponseAsync(channel: Channel, status: HTTPResponseStatus, headers: HTTPHeaders? = nil) async {
		let response = HTTPResponseHead(version: .http1_1,
									 status: status,
									 headers: headers ?? HTTPHeaders())
		
		_ = channel.write(HTTPServerResponsePart.head(response))
		_ = channel.write(HTTPServerResponsePart.end(nil))
		channel.flush()
	}
	
	// MARK: - OpenAPI Handlers
	
	private func handleAIPluginManifest(context: ChannelHandlerContext, head: HTTPRequestHead) {
		
		precondition(head.method == .GET)
		precondition(transport.serveOpenAPI)

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

		let description = transport.server.serverDescription ?? "MCP Server providing tools for automation and integration"
		
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
		
		precondition(head.method == .GET)
		precondition(transport.serveOpenAPI)

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
		precondition(head.method == .POST)
		precondition(transport.serveOpenAPI)

		// Create channel reference and extract necessary data before Task
		let channel = context.channel
		let requestHead = head
		let requestBody = body
		let allocator = context.channel.allocator

		Task {
			await handleToolCallAsync(channel: channel,
									allocator: allocator,
									head: requestHead,
									body: requestBody)
		}
	}

	private func handleToolCallAsync(channel: Channel,
								   allocator: ByteBufferAllocator,
								   head: HTTPRequestHead,
								   body: ByteBuffer?) async {
		// Split the URI into components and validate the necessary parts
		let pathComponents = head.uri.split(separator: "/").map(String.init)

		guard
			pathComponents.count == 2,
			let serverComponent = pathComponents.first,
			let toolName = pathComponents.dropFirst().first,
			serverComponent == transport.server.serverName.asModelName
		else {
			await sendResponseAsync(channel: channel, status: .notFound)
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
			var buffer = allocator.buffer(capacity: data.count)
			buffer.writeBytes(data)
			
			await sendResponseAsync(channel: channel, status: .unauthorized, body: buffer)
			return
		}
		
		// Must have a body
		guard let body = body else {
			await sendResponseAsync(channel: channel, status: .badRequest)
			return
		}

		// Get Data from ByteBuffer
		let bodyData = Data(buffer: body)
		
		do {
			// Parse request body as JSON dictionary
			guard let arguments = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Codable & Sendable] else {
				throw MCPToolError.invalidJSONDictionary
			}
			
			// Call the tool
			let result = try await transport.server.callTool(toolName, arguments: arguments)
			
			// Convert result to JSON data
			let jsonData = try JSONEncoder().encode(result)
			
			var buffer = allocator.buffer(capacity: jsonData.count)
			buffer.writeBytes(jsonData)
			
			await sendResponseAsync(channel: channel, status: .ok, body: buffer)
			
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
			
			await sendResponseAsync(channel: channel, status: status, body: buffer)
		}
	}

	/// Async version of sendResponse that works with Channel instead of ChannelHandlerContext
	private func sendResponseAsync(channel: Channel, status: HTTPResponseStatus, headers: HTTPHeaders? = nil, body: ByteBuffer? = nil) async {
		var responseHeaders = headers ?? HTTPHeaders()
		
		if body != nil {
			responseHeaders.add(name: "Content-Type", value: "application/json")
		}
		
		responseHeaders.add(name: "Access-Control-Allow-Origin", value: "*")
		
		let head = HTTPResponseHead(version: .http1_1, status: status, headers: responseHeaders)
		_ = channel.write(HTTPServerResponsePart.head(head))
		
		if let body = body {
			_ = channel.write(HTTPServerResponsePart.body(.byteBuffer(body)))
		}
		
		_ = channel.write(HTTPServerResponsePart.end(nil))
		channel.flush()
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
		let channel = context.channel
		var responseHeaders = headers ?? HTTPHeaders()
		
		if body != nil {
			responseHeaders.add(name: "Content-Type", value: "application/json")
		}
		
		responseHeaders.add(name: "Access-Control-Allow-Origin", value: "*")
		
		let head = HTTPResponseHead(version: .http1_1, status: status, headers: responseHeaders)
		channel.write(HTTPServerResponsePart.head(head), promise: nil)
		
		if let body = body {
			channel.write(HTTPServerResponsePart.body(.byteBuffer(body)), promise: nil)
		}
		
		channel.write(HTTPServerResponsePart.end(nil), promise: nil)
		channel.flush()
	}
}

// extension ChannelHandlerContext: @retroactive @unchecked Sendable {}
