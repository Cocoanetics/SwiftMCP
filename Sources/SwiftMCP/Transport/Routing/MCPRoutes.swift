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
		if !acceptHeader.isEmpty && !("application/json".matchesAcceptHeader(acceptHeader) || "*/*".matchesAcceptHeader(acceptHeader)) {
			logger.warning("Rejected non-json request (Accept: \(acceptHeader))")
			return textResponse(status: .badRequest, body: "Client must accept application/json.")
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

			if let errorResponse = await validateHTTPProtocolVersion(for: request, sessionID: authSessionID) {
				return errorResponse
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
			let session = await sessionManager.session(id: sessionID)
			await bindBearerTokenIfNeeded(token, to: sessionID)
			let containsRequests = batchContainsRequests(messages)

			if containsRequests {
				guard "text/event-stream".matchesAcceptHeader(acceptHeader) || "*/*".matchesAcceptHeader(acceptHeader) else {
					return textResponse(status: .badRequest, body: "Client must accept text/event-stream.", sessionID: sessionID)
				}

				let (stream, streamInfo) = await createSSEStream(sessionID: sessionID, kind: .request)
				let streamContext = OutboundStreamContext(streamID: streamInfo.streamID, kind: .request)

				Task {
					let responses = await session.work(onStream: streamContext) { _ in
						await self.server.processBatch(messages, ignoringEmptyResponses: true)
					}

					for response in responses {
						_ = try? await self.sendJSONRPC(response, to: streamInfo.streamID)
					}

					await self.finishSSEStream(streamInfo.streamID)
				}

				let headers: [(String, String)] = [
					("Content-Type", "text/event-stream"),
					("Cache-Control", "no-cache"),
					("Connection", "keep-alive"),
					("Mcp-Session-Id", sid),
				]

				return RouteResponse(status: .ok, headers: headers, bodyStream: stream, streamInfo: streamInfo)
			}

			_ = await session.work { _ in
				await self.server.processBatch(messages, ignoringEmptyResponses: true)
			}

			return RouteResponse(status: .accepted, headers: [("Mcp-Session-Id", sid)])
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
			if isLegacy {
				sessionID = UUID()
				authSessionID = nil
			} else {
				return textResponse(status: .badRequest, body: "Missing Mcp-Session-Id. Send initialize first.")
			}
		case .existing(let existingSessionID):
			sessionID = existingSessionID
			authSessionID = existingSessionID
		case .malformed:
			return textResponse(status: .badRequest, body: "Invalid Mcp-Session-Id header.")
		case .unknown:
			return textResponse(status: .notFound, body: "Unknown session. Send initialize first.")
		}

		if let errorResponse = await validateHTTPProtocolVersion(for: request, sessionID: authSessionID) {
			return errorResponse
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

		await bindBearerTokenIfNeeded(token, to: sessionID)
		let stream: AsyncStream<Data>
		let streamInfo: StreamRouteResponseInfo

		if isLegacy {
			(stream, streamInfo) = await createSSEStream(sessionID: sessionID, kind: .legacyGeneral)
		} else if let lastEventID = request.header("Last-Event-ID") ?? request.header("last-event-id") {
			do {
				(stream, streamInfo) = try await resumeSSEStream(sessionID: sessionID, lastEventID: lastEventID)
			} catch SessionManager.StreamResumeError.malformedEventID {
				return textResponse(status: .badRequest, body: "Malformed Last-Event-ID header.", sessionID: sessionID)
			} catch SessionManager.StreamResumeError.sessionMismatch,
			        SessionManager.StreamResumeError.unknownStream,
			        SessionManager.StreamResumeError.resumePointUnavailable {
				return textResponse(status: .notFound, body: "Unknown or expired resumable stream.", sessionID: sessionID)
			} catch {
				return textResponse(status: .internalServerError, body: "Failed to resume stream.", sessionID: sessionID)
			}
		} else {
			(stream, streamInfo) = await createSSEStream(sessionID: sessionID, kind: .general)
		}

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

		return RouteResponse(status: .ok, headers: headers, bodyStream: stream, streamInfo: streamInfo)
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
