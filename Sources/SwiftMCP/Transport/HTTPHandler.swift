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
		
		let channel = context.channel
		
		switch (head.method, head.uri) {
				
			// Handle all OPTIONS requests in one case
			case (.OPTIONS, _):
				handleOPTIONS(channel: context.channel, head: head)

			// Streamable HTTP Endpoint
			case (.POST, let path) where path.hasPrefix("/mcp"):
				Task {
					await self.handleSimpleResponse(channel: channel, head: head, body: body)
				}
				
			case (.GET, let path) where path.hasPrefix("/mcp"):
				handleSSE(context: context, head: head, body: body, sendEndpoint: false)
				
			// SSE Endpoint
				
			case (.GET, let path) where path.hasPrefix("/sse"):
				handleSSE(context: context, head: head, body: body)
				
			case (_, let path) where path.hasPrefix("/sse"):
				sendResponse(channel: context.channel, status: .methodNotAllowed)
				
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
				sendResponse(channel: context.channel, status: .methodNotAllowed)
				
			// if OpenAPI is disabled: everything else is NOT FOUND
				
			case (_, _) where !transport.serveOpenAPI:
				sendResponse(channel: context.channel, status: .notFound)
				
			// AI Plugin Manifest (OpenAPI)
				
			case (.GET, "/.well-known/ai-plugin.json"):
				handleAIPluginManifest(context: context, head: head)
				
			case (_, "/.well-known/ai-plugin.json"):
				sendResponse(channel: context.channel, status: .methodNotAllowed)
				
			// OpenAPI Spec
				
			case (.GET, "/openapi.json"):
				handleOpenAPISpec(channel: context.channel, head: head)
				
			case (_, "/openapi.json"):
				sendResponse(channel: context.channel, status: .methodNotAllowed)
				
			// Tool Endpoint
			case (.POST, let path) where path.hasPrefix(serverPath):
				handleToolCall(context: context, head: head, body: body)
				
			case (_, let path) where path.hasPrefix(serverPath):
				sendResponse(channel: context.channel, status: .methodNotAllowed)
				
				// Fallback for unknown endpoints
			default:
				sendResponse(channel: context.channel, status: .notFound)
		}
	}
	
	private func handleSimpleResponse(channel: Channel, head: HTTPRequestHead, body: ByteBuffer?) async {
		precondition(head.method == .POST)

		// Extract or generate client ID
		let clientId = head.headers["Mcp-Session-Id"].first ?? UUID().uuidString
		
		var headers = HTTPHeaders()
		headers.add(name: "Content-Type", value: "application/json")
		headers.add(name: "Access-Control-Allow-Origin", value: "*")
		headers.add(name: "Mcp-Session-Id", value: clientId)

		// Validate Accept header
		let acceptHeader = head.headers["accept"].first ?? ""
		guard acceptHeader.lowercased().contains("application/json") else {
			logger.warning("Rejected non-json request (Accept: \(acceptHeader))")
			let buffer = channel.allocator.buffer(string: "Client must accept application/json.")
			await sendResponseAsync(channel: channel, status: .badRequest, headers: headers, body: buffer)
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
			let errorMessage = JSONRPCErrorResponse(id: nil, error: .init(code: 401, message: "Unauthorized: \(message)"))
			await sendJSONResponse(channel: channel, status: .unauthorized, json: errorMessage, sessionId: clientId)
			return
		}

		guard let body = body else {
			logger.error("POST /mcp received no body.")
			let buffer = channel.allocator.buffer(string: "Request body required.")
			await sendResponseAsync(channel: channel, status: .badRequest, headers: headers, body: buffer)
			return
		}

		do {
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			
			// First try to decode as a regular JSONRPCMessage
			let request = try decoder.decode(JSONRPCMessage.self, from: body)
			
			// Check if it's an empty ping response (regular response with empty result)
			if case .response(let responseData) = request,
			   let result = responseData.result,
			   result.isEmpty {
				// Empty ping response - send 202 Accepted with client ID
				await sendResponseAsync(channel: channel, status: .accepted, headers: headers, body: nil)
				return
			}

			// Call the server handler (assume async)
			guard let response = await transport.server.handleRequest(request) else {
				// No response to send (e.g., notification)
				await sendResponseAsync(channel: channel, status: .accepted, headers: headers, body: nil)
				return
			}

			print(response)
			await sendJSONResponse(channel: channel, status: .ok, json: response, sessionId: clientId)
		} catch {
			logger.error("Failed to decode or handle JSON-RPC message: \(error)")
			let response = JSONRPCErrorResponse(id: nil, error: .init(code: -32600, message: "Invalid Request: \(error)"))
			await sendJSONResponse(channel: channel, status: .badRequest, json: response, sessionId: clientId)
		}
	}
	
	private func sendJSONResponse<T: Encodable>(
		channel: Channel,
		status: HTTPResponseStatus,
		json: T,
		sessionId: String? = nil
	) async {
		do {
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601WithTimeZone
			let jsonData = try encoder.encode(json)
			var buffer = channel.allocator.buffer(capacity: jsonData.count)
			buffer.writeBytes(jsonData)
			
			var headers = HTTPHeaders()
			headers.add(name: "Content-Type", value: "application/json")
			headers.add(name: "Access-Control-Allow-Origin", value: "*")
			if let sessionId = sessionId {
				headers.add(name: "Mcp-Session-Id", value: sessionId)
			}
			
			await sendResponseAsync(channel: channel, status: status, headers: headers, body: buffer)
		} catch {
			logger.error("Error encoding response: \(error.localizedDescription)")
			// Don't try to send another response here - encoding failures should be handled at a higher level
			// The channel may already have started writing the response
		}
	}
	
	private func handleSSE(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?, sendEndpoint: Bool = true) {
		
		precondition(head.method == .GET)
		
		// Extract or generate session/client ID (they are the same thing)
		let sessionId = head.headers["Mcp-Session-Id"].first ?? UUID().uuidString
		let clientId = sessionId  // Client ID and session ID are the same
		
		// Validate SSE headers
		let acceptHeader = head.headers["accept"].first ?? ""
		
		guard "text/event-stream".matchesAcceptHeader(acceptHeader) else {
			logger.warning("Rejected non-SSE request (Accept: \(acceptHeader))")
			sendResponse(channel: context.channel, status: .badRequest)
			return
		}
		
		let remoteAddress = context.channel.remoteAddress?.description ?? "unknown"
		let userAgent = head.headers["user-agent"].first ?? "unknown"
		
		self.clientId = clientId
		
		logger.info("""
			SSE connection attempt:
			- Client/Session ID: \(clientId)
			- Remote: \(remoteAddress)
			- User-Agent: \(userAgent)
			- Accept: \(acceptHeader)
			- Protocol: \(sendEndpoint ? "Old (HTTP+SSE)" : "New (Streamable HTTP)")
			""")
		
		// Register the channel with client ID
		logger.info("Registering SSE channel for client \(clientId)")
		transport.registerSSEChannel(context.channel, id: UUID(uuidString: clientId)!)
		
		// Set up SSE response headers (ALWAYS send these for any SSE request)
		var headers = HTTPHeaders()
		headers.add(name: "Content-Type", value: "text/event-stream")
		headers.add(name: "Cache-Control", value: "no-cache")
		headers.add(name: "Connection", value: "keep-alive")
		headers.add(name: "Access-Control-Allow-Methods", value: "GET")
		headers.add(name: "Access-Control-Allow-Headers", value: "*")
		
		// Include session ID in response headers for new protocol
		if !sendEndpoint {
			headers.add(name: "Mcp-Session-Id", value: sessionId)
		}
		
		let response = HTTPResponseHead(version: head.version,
									 status: .ok,
									 headers: headers)
		
		logger.info("Sending SSE response headers")
		context.write(wrapOutboundOut(.head(response)), promise: nil)
		context.flush()
		
		// Conditionally send endpoint event (only for old protocol)
		if sendEndpoint {
			guard let endpointUrl = self.endpointUrl(from: head, clientId: clientId) else {
				logger.error("Failed to construct endpoint URL")
				context.close(promise: nil)
				return
			}
			
			logger.info("Sending endpoint event with URL: \(endpointUrl)")
			let message = SSEMessage(name: "endpoint", data: endpointUrl.absoluteString)
			context.channel.sendSSE(message)
		}
		
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
			let errorMessage = JSONRPCErrorResponse(id: nil, error: .init(code: 401, message: "Unauthorized: \(message)"))
			
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
		
		// Send Accepted first
		await sendResponseAsync(channel: channel, status: .accepted)
		
		do {
			let decoder = JSONDecoder()
			decoder.dateDecodingStrategy = .iso8601
			
			// First try to decode as a regular JSONRPCMessage
			let request = try decoder.decode(JSONRPCMessage.self, from: body)
			
			// Check if it's an empty ping response (regular response with empty result) - ignore it
			if case .response(let responseData) = request,
			   let result = responseData.result,
			   result.isEmpty {
				return
			}

			// Handle the response with client ID
			transport.handleJSONRPCRequest(request, from: clientId)
			
		} catch {
			logger.error("Failed to decode JSON-RPC message: \(error)")
			await sendResponseAsync(channel: channel, status: .badRequest)
		}
	}
	
	/// Async version of sendResponse that works with Channel instead of ChannelHandlerContext
	private func sendResponseAsync(channel: Channel, status: HTTPResponseStatus, headers: HTTPHeaders? = nil, body: ByteBuffer? = nil) async {
		let response = HTTPResponseHead(version: .http1_1,
									 status: status,
									 headers: headers ?? HTTPHeaders())
		
		_ = channel.write(HTTPServerResponsePart.head(response))
		if let body = body {
			_ = channel.write(HTTPServerResponsePart.body(.byteBuffer(body)))
		}
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
			
			sendResponse(channel: context.channel, status: .ok, body: buffer)
		} catch {
			logger.error("Failed to encode AI plugin manifest: \(error)")
			sendResponse(channel: context.channel, status: .internalServerError)
		}
	}
	
	private func handleOpenAPISpec(channel: Channel, head: HTTPRequestHead) {
		
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
			var buffer = channel.allocator.buffer(capacity: jsonData.count)
			buffer.writeBytes(jsonData)
			
			sendResponse(channel: channel, status: .ok, body: buffer)
		} catch {
			logger.error("Failed to encode OpenAPI spec: \(error)")
			sendResponse(channel: channel, status: .internalServerError)
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
			guard let arguments = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Sendable] else {
				throw MCPToolError.invalidJSONDictionary
			}
			
			// Try to call as a tool first
			let result: Encodable & Sendable
			
			if let toolProvider = transport.server as? MCPToolProviding,
			   toolProvider.mcpToolMetadata.contains(where: { $0.name == toolName }) {
				// Call as a tool function
				result = try await toolProvider.callTool(toolName, arguments: arguments)
			} else if let resourceProvider = transport.server as? MCPResourceProviding,
					  resourceProvider.mcpResourceMetadata.contains(where: { $0.functionMetadata.name == toolName }) {
				// Call as a resource function
				result = try await resourceProvider.callResourceAsFunction(toolName, arguments: arguments)
			} else {
				// Function not found
				throw MCPToolError.unknownTool(name: toolName)
			}
			
			// Convert MCPResourceContent to OpenAIFileResponse if applicable
			let responseToEncode: Encodable
			
			if let resourceContent = result as? MCPResourceContent {
				
				let file = FileContent(
					name: resourceContent.uri.lastPathComponent,
					mimeType: resourceContent.mimeType ?? "application/octet-stream",
					content: resourceContent.blob ?? resourceContent.text?.data(using: .utf8) ?? Data()
				)
				
				responseToEncode = OpenAIFileResponse(files: [file])
			}
			else if let resourceContentArray = result as? [MCPResourceContent] {
				
				let files = resourceContentArray.compactMap { resourceContent in
					FileContent(
						name: resourceContent.uri.lastPathComponent,
						mimeType: resourceContent.mimeType ?? "application/octet-stream",
						content: resourceContent.blob ?? resourceContent.text?.data(using: .utf8) ?? Data()
					)
				}

				responseToEncode = OpenAIFileResponse(files: files)
			}
			
			else {
				responseToEncode = result
			}
			
			// Convert result to JSON data
			let encoder = JSONEncoder()
			encoder.dateEncodingStrategy = .iso8601WithTimeZone
			encoder.outputFormatting = [.prettyPrinted]
			
			let jsonData = try encoder.encode(responseToEncode)
			
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
	
	private func handleOPTIONS(channel: Channel, head: HTTPRequestHead) {
		logger.info("Handling OPTIONS request for URI: \(head.uri)")
		var headers = HTTPHeaders()
		headers.add(name: "Access-Control-Allow-Methods", value: "GET, POST, OPTIONS")
		headers.add(name: "Access-Control-Allow-Headers", value: "Content-Type, Authorization")
		sendResponse(channel: channel, status: .ok, headers: headers)
	}
	
	private func sendResponse(channel: Channel, status: HTTPResponseStatus, headers: HTTPHeaders? = nil, body: ByteBuffer? = nil) {
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
