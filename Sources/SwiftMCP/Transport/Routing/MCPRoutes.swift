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
		let sessionHeader = await resolveSessionHeader(for: request)
		switch sessionHeader {
		case .malformed:
			return textResponse(status: .badRequest, body: "Invalid Mcp-Session-Id header.")
		case .unknown:
			return textResponse(status: .notFound, body: "Unknown session. Send initialize first.")
		case .missing, .existing:
			break
		}

		// Validate Accept header
		let acceptHeader = request.header("accept") ?? request.header("Accept") ?? ""
		if !acceptHeader.isEmpty {
			let lower = acceptHeader.lowercased()
			guard lower.contains("application/json") || lower.contains("*/*") else {
				logger.warning("Rejected non-json request (Accept: \(acceptHeader))")
				return textResponse(status: .badRequest, body: "Client must accept application/json.")
			}
		}

		guard let body = request.body else {
			logger.error("POST /mcp received no body.")
			return textResponse(status: .badRequest, body: "Request body required.")
		}

		do {
			let messages = try JSONRPCMessage.decodeMessages(from: body)
			let token = request.bearerToken

			let sessionID: UUID
			let authSessionID: UUID?

				if case .missing = sessionHeader {
					guard SessionInitializationGate.batchStartsWithInitialize(messages) else {
						logger.warning("Rejected request without session ID before initialize")
						return textResponse(status: .badRequest, body: "Missing Mcp-Session-Id. Send initialize first.")
					}
					sessionID = UUID()
					authSessionID = nil
				} else if case .existing(let existingSessionID) = sessionHeader {
					if await sessionNeedsInitialize(existingSessionID), !SessionInitializationGate.batchStartsWithInitialize(messages) {
						logger.warning("Rejected request for uninitialized session \(existingSessionID)")
						return textResponse(
							status: .badRequest,
							body: "Session not initialized. Send initialize first.",
						sessionID: existingSessionID
					)
					}
					sessionID = existingSessionID
					authSessionID = existingSessionID
				} else {
					return textResponse(status: .internalServerError, body: "Session validation failed.")
				}

            let authResult = await authorize(token, sessionID: authSessionID)
            switch authResult {
                case .unauthorized(let message):
                    let errorMessage = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: "Unauthorized: \(message)"))
                    return .json(errorMessage, status: .unauthorized, sessionId: authSessionID?.uuidString)
                case .jweNotSupported(let message):
                    let errorMessage = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: message))
                    return .json(errorMessage, status: .forbidden, sessionId: authSessionID?.uuidString)
                case .authorized:
                    break
            }

			let sid = sessionID.uuidString
			let baseHeaders: [(String, String)] = [
				("Content-Type", "application/json"),
				("Mcp-Session-Id", sid),
			]

			let session = await sessionManager.session(id: sessionID)
			await bindBearerTokenIfNeeded(token, to: sessionID)

			let result: RouteResponse = await session.work { session in

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
			let sessionID: String? = {
				if case .existing(let existingSessionID) = sessionHeader {
					return existingSessionID.uuidString
				}
				return nil
			}()
			return .json(response, status: .badRequest, sessionId: sessionID)
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
		let sessionHeader = await resolveSessionHeader(for: request)
		let sessionID: UUID
		let authSessionID: UUID?

        switch sessionHeader {
            case .missing:
                sessionID = UUID()
                authSessionID = nil
            case .existing(let existingSessionID):
                sessionID = existingSessionID
                authSessionID = existingSessionID
            case .malformed:
                return textResponse(status: .badRequest, body: "Invalid Mcp-Session-Id header.")
            case .unknown:
                return textResponse(status: .notFound, body: "Unknown session. Send initialize first.")
        }

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

		let authResult = await authorize(token, sessionID: authSessionID)
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
		await bindBearerTokenIfNeeded(token, to: sessionID)

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

		return RouteResponse(status: .ok, headers: headers, bodyStream: stream, streamSessionID: sessionID)
	}

	/// Handle DELETE /mcp — remove a session.
	func handleDeleteSession(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {
		switch await resolveSessionHeader(for: request) {
		case .missing, .malformed:
			return textResponse(status: .badRequest, body: "Valid Mcp-Session-Id header required.")
		case .unknown:
			return textResponse(status: .notFound, body: "Unknown session. Send initialize first.")
		case .existing(let sessionID):
			await sessionManager.removeSession(id: sessionID)
			return RouteResponse(status: .noContent)
		}
	}
}
