import Foundation


/// New streamable HTTP MCP protocol routes (`/mcp`).
extension HTTPSSETransport {

	/// Returns the streamable HTTP MCP routes.
	func mcpRoutes() -> [HTTPRoute] {
		[
			// POST /mcp — streamable HTTP endpoint for JSON-RPC
			HTTPRoute(.POST, "/mcp", calling: HTTPSSETransport.handleStreamableHTTP),

			// GET /mcp — SSE connection (new streamable HTTP protocol)
			HTTPRoute(.GET, "/mcp", calling: HTTPSSETransport.handleSSE),

			// DELETE /mcp — session removal
			HTTPRoute(.DELETE, "/mcp", calling: HTTPSSETransport.handleDeleteSession),
		]
	}

	// MARK: - Handler Implementations

	/// Handle POST /mcp — streamable HTTP endpoint.
	func handleStreamableHTTP(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {

		// Extract or generate session ID
		let sessionID = UUID(uuidString: request.sessionID ?? "") ?? UUID()
		let sid = sessionID.uuidString

		let baseHeaders: [(String, String)] = [
			("Content-Type", "application/json"),
			("Mcp-Session-Id", sid),
		]

		// Validate Accept header
		let acceptHeader = request.header("accept") ?? request.header("Accept") ?? ""
		if !acceptHeader.isEmpty {
			let lower = acceptHeader.lowercased()
			guard lower.contains("application/json") || lower.contains("*/*") else {
				logger.warning("Rejected non-json request (Accept: \(acceptHeader))")
				return RouteResponse(status: .badRequest, headers: baseHeaders, body: Data("Client must accept application/json.".utf8))
			}
		}

		// Check authorization
		let token = request.bearerToken

		let authResult = await authorize(token, sessionID: sessionID)
		switch authResult {
		case .unauthorized(let message):
			let errorMessage = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: "Unauthorized: \(message)"))
			return .json(errorMessage, status: .unauthorized, sessionId: sid)
		case .jweNotSupported(let message):
			let errorMessage = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: message))
			return .json(errorMessage, status: .forbidden, sessionId: sid)
		case .authorized:
			break
		}

		guard let body = request.body else {
			logger.error("POST /mcp received no body.")
			return RouteResponse(status: .badRequest, headers: baseHeaders, body: Data("Request body required.".utf8))
		}

		do {
			let messages = try JSONRPCMessage.decodeMessages(from: body)

			let result: RouteResponse = await sessionManager.session(id: sessionID).work { session in

				if await session.hasActiveConnection {
					// Process messages and stream responses via SSE
					for message in messages {
						switch message {
						case .response, .errorResponse:
							await session.handleResponse(message)
						default:
							self.handleJSONRPCRequest(message, from: sessionID)
						}
					}

					// Send 202 Accepted — no body needed
					return RouteResponse(status: .accepted, headers: baseHeaders)
				} else {
					// No SSE connection - use immediate HTTP response
					let pending = self.server is MCPFileUploadHandling ? self.pendingUploadStore : nil
					let responses = await PendingUploadResolver.$current.withValue(pending) {
						await self.server.processBatch(messages, ignoringEmptyResponses: true)
					}

					if responses.isEmpty {
						return RouteResponse(status: .accepted, headers: baseHeaders)
					} else if responses.count == 1 {
						return .json(responses.first!, status: .ok, sessionId: sid)
					} else {
						return .json(responses, status: .ok, sessionId: sid)
					}
				}
			}

			return result
		} catch {
			logger.error("Failed to decode JSON-RPC message: \(error)")
			let response = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32700, message: error.localizedDescription))
			return .json(response, status: .badRequest, sessionId: sid)
		}
	}

	/// Handle GET /mcp — SSE connection for streamable HTTP.
	/// Also used by legacy SSE routes for `GET /sse`.
	///
	/// Returns a streaming response whose `AsyncStream<Data>` body stays open
	/// for the lifetime of the SSE connection. SSE events are yielded into the
	/// stream by `Session.sendSSE`.
	func handleSSE(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {
		let isLegacy = request.path == "/sse"
		let sessionID = UUID(uuidString: request.sessionID ?? "") ?? UUID()

		// Validate SSE headers
		let acceptHeader = request.header("accept") ?? request.header("Accept") ?? ""
		guard "text/event-stream".matchesAcceptHeader(acceptHeader) else {
			logger.warning("Rejected non-SSE request (Accept: \(acceptHeader))")
			return RouteResponse(status: .badRequest)
		}

		let userAgent = request.header("User-Agent") ?? request.header("user-agent") ?? "unknown"

		logger.info("""
			SSE connection attempt:
			- Client/Session ID: \(sessionID)
			- User-Agent: \(userAgent)
			- Accept: \(acceptHeader)
			- Protocol: \(isLegacy ? "Old (HTTP+SSE)" : "New (Streamable HTTP)")
			""")

		// Validate token
		let token = request.bearerToken

		let authResult = await authorize(token, sessionID: sessionID)
		switch authResult {
		case .unauthorized(let message):
			logger.warning("Unauthorized SSE connect: \(message)")
			return RouteResponse(status: .unauthorized)
		case .jweNotSupported(let message):
			logger.warning("JWE token not supported for SSE connect: \(message)")
			return RouteResponse(status: .forbidden)
		case .authorized:
			break
		}

		// Create the SSE stream — events will be yielded into it by Session.sendSSE
		let stream = await prepareSSEStream(sessionID: sessionID)

		// For the legacy protocol, send the endpoint event as the first stream item
		if isLegacy {
			if let endpointUrl = endpointUrl(from: request, sessionID: sessionID) {
				logger.info("Sending endpoint event with URL: \(endpointUrl)")
				let message = SSEMessage(data: endpointUrl.absoluteString, eventName: "endpoint")
				sendSSE(message, to: sessionID)
			} else {
				logger.error("Failed to construct endpoint URL")
				return RouteResponse(status: .internalServerError)
			}
		}

		logger.info("SSE connection setup complete for client \(sessionID)")

		// Build SSE response headers
		var headers: [(String, String)] = [
			("Content-Type", "text/event-stream"),
			("Cache-Control", "no-cache"),
			("Connection", "keep-alive"),
			("Access-Control-Allow-Methods", "GET"),
			("Access-Control-Allow-Headers", "Content-Type, Authorization, MCP-Protocol-Version"),
		]

		if !isLegacy {
			headers.append(("Mcp-Session-Id", sessionID.uuidString))
		}

		return RouteResponse(status: .ok, headers: headers, bodyStream: stream)
	}

	/// Handle DELETE /mcp — remove a session.
	func handleDeleteSession(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {
		guard let sessionIDHeader = request.sessionID,
			  let sessionUUID = UUID(uuidString: sessionIDHeader) else {
			return RouteResponse(status: .badRequest)
		}
		await sessionManager.removeSession(id: sessionUUID)
		return RouteResponse(status: .noContent)
	}
}
