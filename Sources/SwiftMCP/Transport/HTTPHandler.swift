import Foundation
@preconcurrency import NIOCore
import NIOHTTP1
import Logging


/// HTTP request handler for the SSE transport
final class HTTPHandler: NSObject, ChannelInboundHandler, Identifiable, @unchecked Sendable, URLSessionTaskDelegate {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private var requestState: RequestState = .idle
    private let transport: HTTPSSETransport
    let id = UUID()
    private var sessionID: UUID?

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
                handleOPTIONS(channel: context.channel, head: head)

            // Streamable HTTP Endpoint
            case (.POST, let path) where path.hasPrefix("/mcp"):
                let channel = context.channel
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
                let channel = context.channel
                Task {
                    await self.handleMessagesAsync(channel: channel, head: head, body: body)
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

            // OAuth metadata
            case (.GET, "/.well-known/oauth-authorization-server"):
                handleOAuthAuthorizationServer(channel: context.channel)

            case (.GET, "/.well-known/oauth-protected-resource"):
                handleOAuthProtectedResource(channel: context.channel, head: head)

            case (_, "/.well-known/oauth-authorization-server"),
                 (_, "/.well-known/oauth-protected-resource"):
                sendResponse(channel: context.channel, status: .methodNotAllowed)

            // --- OAuth Bridge for ChatGPT Plugin ---
            
            case (.GET, let path) where path.hasPrefix("/authorize"):
                let channel = context.channel
                Task {
                    await self.handleAuthorize(channel: channel, head: head)
                }

            case (.GET, let path) where path.hasPrefix("/oauth/callback"):
                let channel = context.channel
                Task {
                    await self.handleOAuthCallback(channel: channel, head: head)
                }

            case (.POST, "/oauth/token"):
                let channel = context.channel
                Task {
                    await self.handleTokenProxy(channel: channel, head: head, body: body)
                }
                
            // --- End OAuth Bridge ---

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

        // Extract or generate session ID
        let sessionID = UUID(uuidString: head.headers["Mcp-Session-Id"].first ?? "") ?? UUID()

        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "application/json")
        headers.add(name: "Access-Control-Allow-Origin", value: "*")
        headers.add(name: "Mcp-Session-Id", value: sessionID.uuidString)

        // Validate Accept header
        let acceptHeader = head.headers["accept"].first ?? ""
        guard acceptHeader.lowercased().contains("application/json") else {
            logger.warning("Rejected non-json request (Accept: \(acceptHeader))")
            let buffer = channel.allocator.buffer(string: "Client must accept application/json.")
            await self.sendResponseAsync(channel: channel, status: .badRequest, headers: headers, body: buffer)
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
        if case .unauthorized(let message) = await transport.authorize(token) {
            let errorMessage = JSONRPCMessage.errorResponse(id: nil, error: .init(code: 401, message: "Unauthorized: \(message)"))
            await self.sendJSONResponseAsync(channel: channel, status: .unauthorized, json: errorMessage, sessionId: sessionID.uuidString)
            return
        }

        guard let body = body else {
            logger.error("POST /mcp received no body.")
            let buffer = channel.allocator.buffer(string: "Request body required.")
            await self.sendResponseAsync(channel: channel, status: .badRequest, headers: headers, body: buffer)
            return
        }

        do {
            let messages = try JSONRPCMessage.decodeMessages(from: body)

            let responseHeaders = headers
            await transport.sessionManager.session(id: sessionID).work { session in
                if session.hasActiveConnection {

                    // Send 202 Accepted immediately
                    await self.sendResponseAsync(channel: channel, status: .accepted, headers: responseHeaders, body: nil)

                    // Process messages and stream responses via SSE
                    for message in messages {
                        // Check if it's an empty ping response - ignore it
                        if case .response(let responseData) = message,
                                           let result = responseData.result,
                                           result.isEmpty {
                            continue
                        }

                        transport.handleJSONRPCRequest(message, from: sessionID)
                    }
                } else {
                    // No SSE connection - use immediate HTTP response
                    let responses = await transport.server.processBatch(messages, ignoringEmptyResponses: true)

                    if responses.isEmpty {
                        await self.sendResponseAsync(channel: channel, status: .accepted, headers: responseHeaders)
                    } else {
                        await self.sendJSONResponseAsync(channel: channel, status: .ok, json: responses, sessionId: sessionID.uuidString)
                }
            }
            }
        } catch {
            logger.error("Failed to decode JSON-RPC message: \(error)")
            let response = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32600, message: error.localizedDescription))
            await self.sendJSONResponseAsync(channel: channel, status: .badRequest, json: response, sessionId: sessionID.uuidString)
        }
    }

    private func handleSSE(context: ChannelHandlerContext, head: HTTPRequestHead, body: ByteBuffer?, sendEndpoint: Bool = true) {

        precondition(head.method == .GET)

        // Extract or generate session/client ID (they are the same thing)
        let sessionID = UUID(uuidString: head.headers["Mcp-Session-Id"].first ?? "") ?? UUID()

        // Validate SSE headers
        let acceptHeader = head.headers["accept"].first ?? ""

        guard "text/event-stream".matchesAcceptHeader(acceptHeader) else {
            logger.warning("Rejected non-SSE request (Accept: \(acceptHeader))")
            sendResponse(channel: context.channel, status: .badRequest)
            return
        }

        let remoteAddress = context.channel.remoteAddress?.description ?? "unknown"
        let userAgent = head.headers["user-agent"].first ?? "unknown"

        self.sessionID = sessionID

        logger.info("""
                        SSE connection attempt:
                        - Client/Session ID: \(sessionID)
                        - Remote: \(remoteAddress)
                        - User-Agent: \(userAgent)
                        - Accept: \(acceptHeader)
                        - Protocol: \(sendEndpoint ? "Old (HTTP+SSE)" : "New (Streamable HTTP)")
                        """)

        // Register the channel with client ID
        logger.info("Registering SSE channel for client \(sessionID)")
        transport.registerSSEChannel(context.channel, id: sessionID)


        // Set up SSE response headers (ALWAYS send these for any SSE request)
        var headers = HTTPHeaders()
        headers.add(name: "Content-Type", value: "text/event-stream")
        headers.add(name: "Cache-Control", value: "no-cache")
        headers.add(name: "Connection", value: "keep-alive")
        headers.add(name: "Access-Control-Allow-Methods", value: "GET")
        headers.add(name: "Access-Control-Allow-Headers", value: "*")

        // Include session ID in response headers for new protocol
        if !sendEndpoint {
            headers.add(name: "Mcp-Session-Id", value: sessionID.uuidString)
        }

        let response = HTTPResponseHead(version: head.version,
									 status: .ok,
									 headers: headers)

        logger.info("Sending SSE response headers")
        context.write(wrapOutboundOut(.head(response)), promise: nil)
        context.flush()

        // Conditionally send endpoint event (only for old protocol)
        if sendEndpoint {
            guard let endpointUrl = self.endpointUrl(from: head, sessionID: sessionID) else {
                logger.error("Failed to construct endpoint URL")
                context.close(promise: nil)
                return
            }

            logger.info("Sending endpoint event with URL: \(endpointUrl)")
            let message = SSEMessage(name: "endpoint", data: endpointUrl.absoluteString)
            context.channel.sendSSE(message)
        }

        logger.info("SSE connection setup complete for client \(sessionID)")
    }

    /// Async version of handleMessages that works with Sendable types
    private func handleMessagesAsync(channel: Channel, head: HTTPRequestHead, body: ByteBuffer?) async {
        // Extract client ID from URL path using URLComponents
        guard let components = URLComponents(string: head.uri),
              let idString = components.path.components(separatedBy: "/").last,
              let sessionID = UUID(uuidString: idString),
              components.path.hasPrefix("/messages/") else {
            logger.warning("Invalid message endpoint URL format: \(head.uri)")
            await self.sendResponseAsync(channel: channel, status: .badRequest)
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
        if case .unauthorized(let message) = await transport.authorize(token) {
            let errorMessage = JSONRPCMessage.errorResponse(id: nil, error: .init(code: 401, message: "Unauthorized: \(message)"))

            let data = try! JSONEncoder().encode(errorMessage)
            let errorResponse = String(data: data, encoding: .utf8)!

            // Send error via SSE
            let sseMessage = SSEMessage(data: errorResponse)
            transport.sendSSE(sseMessage, to: sessionID)
        }

        guard let body = body else {
            await self.sendResponseAsync(channel: channel, status: .badRequest)
            return
        }

        // Send Accepted first
        await self.sendResponseAsync(channel: channel, status: .accepted)

        do {
            let messages = try JSONRPCMessage.decodeMessages(from: body)

            for message in messages {
                // Check if it's an empty ping response - ignore it
                if case .response(let responseData) = message,
                                   let result = responseData.result,
                                   result.isEmpty {
                    continue
                }

                transport.handleJSONRPCRequest(message, from: sessionID)
            }
        } catch {
            logger.error("Failed to decode JSON-RPC message in SSE context: \(error)")
        }
    }

    private func sendResponseAsync(channel: Channel, status: HTTPResponseStatus, headers: HTTPHeaders? = nil, body: ByteBuffer? = nil) async {
        var responseHeaders = headers ?? HTTPHeaders()
        responseHeaders.add(name: "Access-Control-Allow-Origin", value: "*")

        if let body = body {
            if responseHeaders["Content-Type"].isEmpty {
                 responseHeaders.add(name: "Content-Type", value: "text/plain; charset=utf-8")
            }
            responseHeaders.add(name: "Content-Length", value: "\(body.readableBytes)")
        } else {
            responseHeaders.add(name: "Content-Length", value: "0")
        }

        let head = HTTPResponseHead(version: .http1_1, status: status, headers: responseHeaders)
        
        channel.write(HTTPServerResponsePart.head(head), promise: nil)
        if let body = body {
            channel.write(HTTPServerResponsePart.body(.byteBuffer(body)), promise: nil)
        }
        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
    }

    private func sendJSONResponseAsync<T: Encodable>(
        channel: Channel,
        status: HTTPResponseStatus,
        json: T,
        sessionId: String? = nil
    ) async {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601WithTimeZone
            encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
            let jsonData = try encoder.encode(json)
            var buffer = channel.allocator.buffer(capacity: jsonData.count)
            buffer.writeBytes(jsonData)

            var headers = HTTPHeaders()
            headers.add(name: "Content-Type", value: "application/json")
            headers.add(name: "Access-Control-Allow-Origin", value: "*")
            if let sessionId = sessionId {
                headers.add(name: "Mcp-Session-Id", value: sessionId)
            }

            await self.sendResponseAsync(channel: channel, status: status, headers: headers, body: buffer)
        } catch {
            logger.error("Error encoding response: \(error.localizedDescription)")
            // If encoding fails, we can't send a JSON error, so send a plain text one.
            let errorBuffer = self.stringBuffer("Internal Server Error encoding response", allocator: channel.allocator)
            await self.sendResponseAsync(channel: channel, status: .internalServerError, body: errorBuffer)
        }
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

    // MARK: - OAuth Metadata

    /// Serve metadata for the OAuth authorization server.
    private func handleOAuthAuthorizationServer(channel: Channel) {
        guard let config = transport.oauthConfiguration else {
            sendResponse(channel: channel, status: .notFound)
            return
        }

        let metadata = config.authorizationServerMetadata()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(metadata)
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            sendResponse(channel: channel, status: .ok, body: buffer)
        } catch {
            logger.error("Failed to encode OAuth metadata: \(error)")
            sendResponse(channel: channel, status: .internalServerError)
        }
    }

    /// Serve metadata for the OAuth protected resource.
    private func handleOAuthProtectedResource(channel: Channel, head: HTTPRequestHead) {
        guard let config = transport.oauthConfiguration else {
            sendResponse(channel: channel, status: .notFound)
            return
        }

        // Build the resource base URL from the incoming request headers
        // Use forwarded headers if present, otherwise use transport defaults
        let host: String
        let scheme: String
        let port: Int

        if let forwardedHost = head.headers["X-Forwarded-Host"].first {
            host = forwardedHost
        } else if let hostHeader = head.headers["Host"].first {
            host = hostHeader
        } else {
            host = transport.host
        }

        if let forwardedProto = head.headers["X-Forwarded-Proto"].first {
            scheme = forwardedProto
        } else {
            scheme = "http"
        }

        if let forwardedPort = head.headers["X-Forwarded-Port"].first, let p = Int(forwardedPort) {
            port = p
        } else {
            port = transport.port
        }

        // Compose the base URL (include port if not default)
        var resourceBaseURL = "\(scheme)://\(host)"
        if !(scheme == "http" && port == 80) && !(scheme == "https" && port == 443) {
            // Only add port if not default for scheme and not already present in host
            if !host.contains(":") {
                resourceBaseURL += ":\(port)"
            }
        }

        let metadata = config.protectedResourceMetadata(resourceBaseURL: resourceBaseURL)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(metadata)
            var buffer = channel.allocator.buffer(capacity: data.count)
            buffer.writeBytes(data)
            sendResponse(channel: channel, status: .ok, body: buffer)
        } catch {
            logger.error("Failed to encode OAuth metadata: \(error)")
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
        if case .unauthorized(let message) = await transport.authorize(token) {
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
            } else if let promptProvider = transport.server as? MCPPromptProviding,
                      promptProvider.mcpPromptMetadata.contains(where: { $0.name == toolName }) {
                // Call as a prompt function
                let messages = try await promptProvider.callPrompt(toolName, arguments: arguments)
                result = messages
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
            encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
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

    // MARK: - OAuth Bridge Handlers
    
    private func handleAuthorize(channel: Channel, head: HTTPRequestHead) async {
        guard let config = transport.oauthConfiguration, let clientID = config.clientID else {
            let buffer = self.stringBuffer("OAuth not configured correctly on server: missing clientID", allocator: channel.allocator)
            await self.sendResponseAsync(channel: channel, status: .internalServerError, body: buffer)
            return
        }

        // 1. Extract original redirect_uri and state from the initial client request
        guard let components = URLComponents(string: head.uri),
              let originalState = components.queryItems?.first(where: { $0.name == "state" })?.value,
              let originalRedirectURI = components.queryItems?.first(where: { $0.name == "redirect_uri" })?.value else {
            let buffer = self.stringBuffer("Missing 'state' or 'redirect_uri' parameter in request from client", allocator: channel.allocator)
            await self.sendResponseAsync(channel: channel, status: .badRequest, body: buffer)
            return
        }

        // 2. Generate a new state for our server to track this request
        let serverState = UUID().uuidString

        // 3. Store the original client info against our new server state
        await transport.sessionManager.storeOAuthState(serverState: serverState, originalRedirectURI: originalRedirectURI, originalState: originalState)

        // 4. Construct the URL to redirect the user to Auth0
        
        // The redirect URI for Auth0 must be our own /oauth/callback endpoint
        var callbackURLComponents = URLComponents()
        callbackURLComponents.scheme = head.headers["X-Forwarded-Proto"].first ?? "http"

        let port: Int?

        if let forwardedHost = head.headers["X-Forwarded-Host"].first {
            callbackURLComponents.host = forwardedHost
            // If we are behind a proxy, only use the forwarded port if it's explicitly set.
            // Otherwise, we assume the standard port for the scheme (e.g., 443 for https).
            if let forwardedPortStr = head.headers["X-Forwarded-Port"].first, let forwardedPort = Int(forwardedPortStr) {
                port = forwardedPort
            } else {
                port = nil
            }
        } else {
            // If not behind a proxy, use the local transport's host and port.
            callbackURLComponents.host = transport.host
            port = transport.port
        }
        
        // Only add the port to the URL if it's non-standard for the scheme.
        if let port = port, !((callbackURLComponents.scheme == "http" && port == 80) || (callbackURLComponents.scheme == "https" && port == 443)) {
            callbackURLComponents.port = port
        }
        
        callbackURLComponents.path = "/oauth/callback"
        
        guard let callbackURL = callbackURLComponents.url else {
             let buffer = self.stringBuffer("Could not construct callback URL", allocator: channel.allocator)
             await self.sendResponseAsync(channel: channel, status: .internalServerError, body: buffer)
             return
        }

        var authURLComponents = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
            URLQueryItem(name: "scope", value: "openid profile email"),
            URLQueryItem(name: "state", value: serverState) // Use our server-generated state
        ]

        if let audience = config.audience {
            queryItems.append(URLQueryItem(name: "audience", value: audience))
        }
        authURLComponents.queryItems = queryItems

        guard let authURL = authURLComponents.url else {
            let buffer = self.stringBuffer("Could not construct authorization URL", allocator: channel.allocator)
            await self.sendResponseAsync(channel: channel, status: .internalServerError, body: buffer)
            return
        }
        
        // 5. Redirect the client to the Auth0 authorization URL
        logger.info("Redirecting client to Auth0 for authorization.")
        var headers = HTTPHeaders()
        headers.add(name: "Location", value: authURL.absoluteString)
        await self.sendResponseAsync(channel: channel, status: .found, headers: headers)
    }

    private func handleOAuthCallback(channel: Channel, head: HTTPRequestHead) async {
        // 1. Extract the authorization code and our server-generated state from Auth0's callback
        guard let components = URLComponents(string: head.uri),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
              let serverState = components.queryItems?.first(where: { $0.name == "state" })?.value else {
            let buffer = self.stringBuffer("Invalid callback from Auth0: missing 'code' or 'state' parameter.", allocator: channel.allocator)
            await self.sendResponseAsync(channel: channel, status: .badRequest, body: buffer)
            return
        }

        // 2. Retrieve the original client's redirect URI and state
        guard let (originalRedirectURI, originalState) = await transport.sessionManager.retrieveOAuthState(serverState: serverState) else {
            let buffer = self.stringBuffer("Invalid or expired 'state' parameter in callback from Auth0.", allocator: channel.allocator)
            await self.sendResponseAsync(channel: channel, status: .badRequest, body: buffer)
            return
        }

        // 3. Construct the final redirect URL for the original client (e.g., ChatGPT)
        guard var gptURLComponents = URLComponents(string: originalRedirectURI) else {
            let buffer = self.stringBuffer("Invalid original redirect URI stored.", allocator: channel.allocator)
            await self.sendResponseAsync(channel: channel, status: .internalServerError, body: buffer)
            return
        }
        
        // Append the code and state to any existing query items.
        if gptURLComponents.queryItems == nil {
            gptURLComponents.queryItems = []
        }
        gptURLComponents.queryItems?.append(URLQueryItem(name: "code", value: code))
        gptURLComponents.queryItems?.append(URLQueryItem(name: "state", value: originalState))
        
        guard let finalURL = gptURLComponents.url else {
            let buffer = self.stringBuffer("Could not construct final client callback URL.", allocator: channel.allocator)
            await self.sendResponseAsync(channel: channel, status: .internalServerError, body: buffer)
            return
        }

        // 4. Redirect the client to the final destination
        logger.info("Redirecting client back to original redirect URI.")
        var headers = HTTPHeaders()
        headers.add(name: "Location", value: finalURL.absoluteString)
        await self.sendResponseAsync(channel: channel, status: .found, headers: headers)
    }

    private func handleTokenProxy(channel: Channel, head: HTTPRequestHead, body: ByteBuffer?) async {
        logger.info("Handling token proxy request")
        guard let config = transport.oauthConfiguration,
              let clientID = config.clientID,
              let clientSecret = config.clientSecret else {
            logger.error("OAuth not configured correctly - missing clientID or clientSecret")
            await self.sendJSONResponseAsync(channel: channel, status: .internalServerError, json: ["error": "OAuth not configured correctly on server"])
            return
        }

        guard let requestBody = body else {
            await self.sendJSONResponseAsync(channel: channel, status: .badRequest, json: ["error": "Missing request body"])
            return
        }
        
        // Prepend '?' to treat the form-urlencoded body as a query string for parsing
        let queryString = "?" + (requestBody.getString(at: requestBody.readerIndex, length: requestBody.readableBytes) ?? "")
        let clientParams = Dictionary(uniqueKeysWithValues: (URLComponents(string: queryString)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        // Reconstruct our server's callback URL, which is what Auth0 expects for the redirect_uri.
        var callbackURLComponents = URLComponents()
        callbackURLComponents.scheme = head.headers["X-Forwarded-Proto"].first ?? "http"
        callbackURLComponents.host = head.headers["X-Forwarded-Host"].first ?? transport.host
        callbackURLComponents.path = "/oauth/callback"
        
        guard let callbackURL = callbackURLComponents.url else {
            logger.error("Could not construct callback URL for token proxy.")
            await self.sendJSONResponseAsync(channel: channel, status: .internalServerError, json: ["error": "Could not construct callback URL for token proxy."])
            return
        }

        // Build the request to Auth0 using server's credentials
        var formBody = URLComponents()
        formBody.queryItems = [
            URLQueryItem(name: "grant_type", value: clientParams["grant_type"]),
            URLQueryItem(name: "code", value: clientParams["code"]),
            URLQueryItem(name: "redirect_uri", value: callbackURL.absoluteString),
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "client_secret", value: clientSecret)
        ]

        var auth0Request = URLRequest(url: config.tokenEndpoint)
        auth0Request.httpMethod = "POST"
        auth0Request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        auth0Request.httpBody = formBody.query?.data(using: .utf8)

        do {
            let (data, response) = try await URLSession.shared.data(for: auth0Request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await self.sendJSONResponseAsync(channel: channel, status: .internalServerError, json: ["error": "Invalid response from auth server"])
                return
            }

            // Forward the response (body and status) from Auth0 back to the client
            var responseBuffer = channel.allocator.buffer(capacity: data.count)
            responseBuffer.writeBytes(data)
            
            var headers = HTTPHeaders()
            // Copy headers from Auth0 response, but exclude problematic ones that describe the payload's transfer,
            // since URLSession has already decoded the payload for us.
            let headersToExclude = ["transfer-encoding", "connection", "content-encoding"]
            httpResponse.allHeaderFields.forEach { key, value in
                if let keyString = key as? String, let valueString = value as? String, !headersToExclude.contains(keyString.lowercased()) {
                     headers.add(name: keyString, value: valueString)
                }
            }
            
            // Set the correct content-length for the DECOMPRESSED data we are sending.
            headers.replaceOrAdd(name: "Content-Length", value: "\(data.count)")
            
            await self.sendResponseAsync(channel: channel, status: HTTPResponseStatus(statusCode: httpResponse.statusCode), headers: headers, body: responseBuffer)
            
        } catch {
            await self.sendJSONResponseAsync(channel: channel, status: .internalServerError, json: ["error": "Failed to proxy request to auth server: \(error.localizedDescription)"])
        }
    }

    // MARK: - URLSessionTaskDelegate
    
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Don't follow redirects. Let the original data task complete with the redirect response.
        logger.info("URLSession delegate detected redirect, preventing follow.")
        completionHandler(nil)
    }

    // MARK: - Helpers

    private func stringBuffer(_ string: String, allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: string.utf8.count)
        buffer.writeString(string)
        return buffer
    }

    private func getBaseURL(from head: HTTPRequestHead) -> String {
        let host: String
        if let forwardedHost = head.headers["X-Forwarded-Host"].first {
            host = forwardedHost
        } else if let hostHeader = head.headers["Host"].first {
            host = hostHeader
        } else {
            host = transport.host
        }

        let scheme: String
        if let forwardedProto = head.headers["X-Forwarded-Proto"].first {
            scheme = forwardedProto
        } else {
            scheme = "http"
        }

        return "\(scheme)://\(host)"
    }
    
    fileprivate func endpointUrl(from head: HTTPRequestHead, sessionID: UUID) -> URL? {
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

        components.path = "/messages/\(sessionID.uuidString)"

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

        channel.writeAndFlush(HTTPServerResponsePart.end(nil), promise: nil)
    }
}
