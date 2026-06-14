#if Server
import Foundation
import HTTPTypes

/// New streamable HTTP MCP protocol routes (`/mcp`).
extension HTTPSSETransport {

	/// Returns the streamable HTTP MCP routes.
	func mcpRoutes() -> [HTTPRoute] {
		[
			// POST /mcp — streamable HTTP endpoint for JSON-RPC
			HTTPRoute(.post, "/mcp", calling: HTTPSSETransport.handleStreamableHTTP),

			// GET /mcp — SSE connection (new streamable HTTP protocol)
			HTTPRoute(.get, "/mcp", calling: HTTPSSETransport.handleSSE),

			// DELETE /mcp — session removal
			HTTPRoute(.delete, "/mcp", calling: HTTPSSETransport.handleDeleteSession)
		]
	}

	// MARK: - Handler Implementations

	/// Resolved request context used by `handleStreamableHTTP` after gate / auth checks.
	private struct StreamableHTTPContext {
		let sessionID: UUID
		let authSessionID: UUID?
		let acceptHeader: String
	}

	/// Handle POST /mcp — streamable HTTP endpoint.
	func handleStreamableHTTP(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {
		let sessionHeader = await resolveSessionHeader(for: request)
		if let earlyResponse = streamableEarlyRejection(for: sessionHeader) {
			return earlyResponse
		}

		// Validate Accept header
		let acceptHeader = request.header("accept") ?? request.header("Accept") ?? ""
		if let acceptError = validateAcceptForStreamableHTTP(acceptHeader: acceptHeader) {
			return acceptError
		}

		guard let body = request.body else {
			logger.error("POST /mcp received no body.")
			return textResponse(status: .badRequest, body: "Request body required.")
		}

		do {
			let messages = try JSONRPCMessage.decodeMessages(from: body)
			let token = request.bearerToken

			guard let context = try await resolveStreamableContext(
				sessionHeader: sessionHeader,
				messages: messages,
				acceptHeader: acceptHeader
			) else {
				return textResponse(status: .internalServerError, body: "Session validation failed.")
			}

			if let errorResponse = await validateHTTPProtocolVersion(for: request, sessionID: context.authSessionID) {
				return errorResponse
			}

			// Reject JSON-RPC batches on protocol revisions that removed batching
			// (2025-06-18 onward). Older/unknown versions still permit them.
			let resolvedVersion = await resolvedHTTPProtocolVersion(for: request, sessionID: context.authSessionID)
			if JSONRPCMessage.batchingRejected(body: body, version: resolvedVersion) {
				let batchError = JSONRPCMessage.errorResponse(
					id: nil,
					error: .init(
						code: -32600,
						message: "JSON-RPC batching is not supported in protocol version \(resolvedVersion)."
					)
				)
				return .json(batchError, status: .badRequest, sessionId: context.authSessionID?.uuidString)
			}

			if let authError = await authorizeRequest(token: token, authSessionID: context.authSessionID) {
				return authError
			}

			return await dispatchStreamable(
				messages: messages,
				token: token,
				context: context
			)
		} catch {
			return decodeFailureResponse(error: error, sessionHeader: sessionHeader)
		}
	}

	/// Early rejection for malformed/unknown session headers.
	private func streamableEarlyRejection(for sessionHeader: SessionHeaderResolution) -> RouteResponse? {
		switch sessionHeader {
		case .malformed:
			return textResponse(status: .badRequest, body: "Invalid Mcp-Session-Id header.")
		case .unknown:
			return textResponse(status: .notFound, body: "Unknown session. Send initialize first.")
		case .missing, .existing:
			return nil
		}
	}

	/// Validate Accept header for the streamable HTTP endpoint.
	private func validateAcceptForStreamableHTTP(acceptHeader: String) -> RouteResponse? {
		let acceptsJSON = "application/json".matchesAcceptHeader(acceptHeader)
		let acceptsAny = "*/*".matchesAcceptHeader(acceptHeader)
		guard acceptHeader.isEmpty || acceptsJSON || acceptsAny else {
			logger.warning("Rejected non-json request (Accept: \(acceptHeader))")
			return textResponse(status: .badRequest, body: "Client must accept application/json.")
		}
		return nil
	}

	/// Resolve the request context from the session header and messages, returning early-response on failure.
	private func resolveStreamableContext(
		sessionHeader: SessionHeaderResolution,
		messages: [JSONRPCMessage],
		acceptHeader: String
	) async throws -> StreamableHTTPContext? {
		switch sessionHeader {
		case .missing:
			guard SessionInitializationGate.batchStartsWithInitialize(messages) else {
				logger.warning("Rejected request without session ID before initialize")
				throw StreamableHTTPError.missingSessionForNonInitialize
			}
			return StreamableHTTPContext(sessionID: UUID(), authSessionID: nil, acceptHeader: acceptHeader)
		case .existing(let existingSessionID):
			if await sessionNeedsInitialize(existingSessionID),
			   !SessionInitializationGate.batchStartsWithInitialize(messages) {
				logger.warning("Rejected request for uninitialized session \(existingSessionID)")
				throw StreamableHTTPError.uninitializedSession(existingSessionID)
			}
			return StreamableHTTPContext(
				sessionID: existingSessionID,
				authSessionID: existingSessionID,
				acceptHeader: acceptHeader
			)
		case .malformed, .unknown:
			return nil
		}
	}

	/// Run authorization for an inbound request and return an error response (if any).
	private func authorizeRequest(token: String?, authSessionID: UUID?) async -> RouteResponse? {
		let authResult = await authorize(token, sessionID: authSessionID)
		switch authResult {
		case .unauthorized(let message):
			let errorMessage = JSONRPCMessage.errorResponse(
				id: nil,
				error: .init(code: -32000, message: "Unauthorized: \(message)")
			)
			return .json(errorMessage, status: .unauthorized, sessionId: authSessionID?.uuidString)
		case .jweNotSupported(let message):
			let errorMessage = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: message))
			return .json(errorMessage, status: .forbidden, sessionId: authSessionID?.uuidString)
		case .authorized:
			return nil
		}
	}

	/// Dispatch the messages either as a streaming SSE response or buffered accepted response.
	private func dispatchStreamable(
		messages: [JSONRPCMessage],
		token: String?,
		context: StreamableHTTPContext
	) async -> RouteResponse {
		let sid = context.sessionID.uuidString
		let session = await sessionManager.session(id: context.sessionID)
		await bindBearerTokenIfNeeded(token, to: context.sessionID)
		let containsRequests = batchContainsRequests(messages)

		if containsRequests {
			guard "text/event-stream".matchesAcceptHeader(context.acceptHeader)
				|| "*/*".matchesAcceptHeader(context.acceptHeader) else {
				return textResponse(
					status: .badRequest,
					body: "Client must accept text/event-stream.",
					sessionID: context.sessionID
				)
			}

			let (stream, streamInfo) = await createSSEStream(sessionID: context.sessionID, kind: .request)
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

			let headerFields: HTTPFields = [
				.contentType: "text/event-stream",
				.cacheControl: "no-cache",
				.connection: "keep-alive",
				.mcpSessionID: sid
			]

			return RouteResponse(status: .ok, headerFields: headerFields, bodyStream: stream, streamInfo: streamInfo)
		}

		_ = await session.work { _ in
			await self.server.processBatch(messages, ignoringEmptyResponses: true)
		}

		return RouteResponse(status: .accepted, headerFields: [.mcpSessionID: sid])
	}

	/// Internal errors thrown while resolving the streamable HTTP context.
	private enum StreamableHTTPError: Error {
		case missingSessionForNonInitialize
		case uninitializedSession(UUID)
	}

	/// Build a response describing why JSON-RPC decoding failed.
	private func decodeFailureResponse(error: Error, sessionHeader: SessionHeaderResolution) -> RouteResponse {
		if let streamableError = error as? StreamableHTTPError {
			switch streamableError {
			case .missingSessionForNonInitialize:
				return textResponse(status: .badRequest, body: "Missing Mcp-Session-Id. Send initialize first.")
			case .uninitializedSession(let id):
				return textResponse(
					status: .badRequest,
					body: "Session not initialized. Send initialize first.",
					sessionID: id
				)
			}
		}

		logger.error("Failed to decode JSON-RPC message: \(error)")
		let response = JSONRPCMessage.errorResponse(
			id: nil,
			error: .init(code: -32700, message: error.localizedDescription)
		)
		let sessionID: String? = {
			if case .existing(let existingSessionID) = sessionHeader {
				return existingSessionID.uuidString
			}
			return nil
		}()
		return .json(response, status: .badRequest, sessionId: sessionID)
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
#endif
