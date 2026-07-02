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
		/// A modern (stateless) request: no `Mcp-Session-Id` is required inbound or
		/// echoed outbound; `sessionID` is an ephemeral id used only to route this
		/// request's SSE stream internally.
		let isModern: Bool
	}

	/// Handle POST /mcp — streamable HTTP endpoint.
	func handleStreamableHTTP(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {
		let sessionHeader = await resolveSessionHeader(for: request)

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

			// A request is modern iff its body's `_meta` declares a modern version —
			// the authoritative per-request identity, matching how the handler
			// resolves the era. A modern `MCP-Protocol-Version` header without a
			// matching `_meta` therefore falls to the legacy path (and its
			// header/session mismatch is rejected there), rather than taking the
			// sessionless path and being served as legacy.
			let isModern = SessionInitializationGate.batchIsModern(messages)

			// Modern preflight: required-header validation (400 + -32001) and the
			// unknown-method check (404 + -32601), both decided before dispatch.
			if isModern, let preflightError = modernPreflightResponse(request: request, messages: messages) {
				return preflightError
			}

			// Modern is sessionless (no inbound Mcp-Session-Id), so a malformed /
			// unknown session header only rejects a legacy request. A well-formed
			// modern request sends no session header, so this is a no-op for it.
			if !isModern, let earlyResponse = streamableEarlyRejection(for: sessionHeader) {
				return earlyResponse
			}

			guard let context = try await resolveStreamableContext(
				sessionHeader: sessionHeader,
				messages: messages,
				acceptHeader: acceptHeader,
				isModern: isModern
			) else {
				return textResponse(status: .internalServerError, body: "Session validation failed.")
			}

			if let errorResponse = await validateHTTPProtocolVersion(for: request, sessionID: context.authSessionID) {
				return errorResponse
			}

			// Reject JSON-RPC batches on protocol revisions that removed batching
			// (2025-06-18 onward); older/unknown versions still permit them.
			if let batchError = await batchingRejectionResponse(
				body: body,
				request: request,
				messages: messages,
				sessionID: context.authSessionID
			) {
				return batchError
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
		acceptHeader: String,
		isModern: Bool
	) async throws -> StreamableHTTPContext? {
		// Modern is stateless: no inbound session is required and none is surfaced.
		// An ephemeral id backs this request's SSE-stream routing only. The init
		// gate does not apply (modern has no `initialize`).
		if isModern {
			return StreamableHTTPContext(
				sessionID: UUID(), authSessionID: nil, acceptHeader: acceptHeader, isModern: true
			)
		}

		switch sessionHeader {
		case .missing:
			guard SessionInitializationGate.batchStartsWithPreInitMethod(messages) else {
				logger.warning("Rejected request without session ID before initialize")
				throw StreamableHTTPError.missingSessionForNonInitialize
			}
			return StreamableHTTPContext(
				sessionID: UUID(), authSessionID: nil, acceptHeader: acceptHeader, isModern: false
			)
		case .existing(let existingSessionID):
			if await sessionNeedsInitialize(existingSessionID),
			   !SessionInitializationGate.batchStartsWithPreInitMethod(messages) {
				logger.warning("Rejected request for uninitialized session \(existingSessionID)")
				throw StreamableHTTPError.uninitializedSession(existingSessionID)
			}
			return StreamableHTTPContext(
				sessionID: existingSessionID,
				authSessionID: existingSessionID,
				acceptHeader: acceptHeader,
				isModern: false
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

	/// Reject a JSON-RPC batch when the governing protocol version removed
	/// batching (`2025-06-18` onward). For a brand-new session the version is
	/// declared inside the leading `initialize`, so `messages` is consulted to
	/// resolve it. Returns a `400` + JSON-RPC `-32600` response, or `nil`.
	///
	/// Shared by the streamable HTTP (`/mcp`) and legacy SSE (`/messages`) POST
	/// handlers so both endpoints gate batches identically.
	internal func batchingRejectionResponse<Body: Sendable>(
		body: Data,
		request: HTTPRouteRequest<Body>,
		messages: [JSONRPCMessage],
		sessionID: UUID?
	) async -> RouteResponse? {
		let version = await resolvedHTTPProtocolVersion(for: request, sessionID: sessionID, messages: messages)
		guard JSONRPCMessage.batchingRejected(body: body, version: version) else {
			return nil
		}

		let error = JSONRPCMessage.errorResponse(
			id: nil,
			error: .init(
				code: -32600,
				message: "JSON-RPC batching is not supported in protocol version \(version)."
			)
		)
		return .json(error, status: .badRequest, sessionId: sessionID?.uuidString)
	}

	/// Dispatch the messages either as a streaming SSE response or buffered accepted response.
	///
	/// A request-bearing POST opens a per-request SSE stream, binds it as the
	/// outbound scope for the duration of dispatch (so the reply *and* any mid-call
	/// notifications land on it), and closes it afterward — the open stream is
	/// returned as the POST body. A notification-only POST is dispatched without a
	/// stream and acknowledged with `202`.
	private func dispatchStreamable(
		messages: [JSONRPCMessage],
		token: String?,
		context: StreamableHTTPContext
	) async -> RouteResponse {
		let sid = context.sessionID.uuidString

		if batchContainsRequests(messages) {
			// Validate Accept BEFORE materializing a session, so a rejection mints
			// nothing (and, for modern, exposes no Mcp-Session-Id).
			guard "text/event-stream".matchesAcceptHeader(context.acceptHeader)
				|| "*/*".matchesAcceptHeader(context.acceptHeader) else {
				return textResponse(
					status: .badRequest,
					body: "Client must accept text/event-stream.",
					sessionID: context.isModern ? nil : context.sessionID
				)
			}

			let session = await sessionManager.session(id: context.sessionID)
			await bindBearerTokenIfNeeded(token, to: context.sessionID)
			// Modern per-request streams are non-resumable: no replay buffer, no
			// `id:` resume anchors on the wire (resume itself is GET-only, which
			// modern already answers with 405).
			let (stream, streamInfo) = await createSSEStream(
				sessionID: context.sessionID, kind: .request, resumable: !context.isModern
			)
			let streamContext = OutboundStreamContext(streamID: streamInfo.streamID, kind: .request)

			Task {
				let responses = await session.work(onStream: streamContext) { _ in
					await self.processInbound(messages)
				}

				for response in responses {
					_ = try? await self.sendJSONRPC(response, to: streamInfo.streamID)
				}

				await self.finishSSEStream(streamInfo.streamID)

				// Modern is sessionless: once this request's stream is done, drop the
				// ephemeral session so modern traffic doesn't accumulate `Session`
				// objects (there is no client `DELETE` to reclaim them).
				if context.isModern {
					await self.sessionManager.removeSession(id: context.sessionID)
				}
			}

			var headerFields: HTTPFields = [
				.contentType: "text/event-stream",
				.cacheControl: "no-cache",
				.connection: "keep-alive"
			]
			// Modern is sessionless (no Mcp-Session-Id echoed) and tells buffering
			// reverse proxies to pass per-request events through immediately; legacy
			// keeps echoing the session id.
			if context.isModern {
				headerFields[.xAccelBuffering] = "no"
			} else {
				headerFields[.mcpSessionID] = sid
			}

			return RouteResponse(status: .ok, headerFields: headerFields, bodyStream: stream, streamInfo: streamInfo)
		}

		let session = await sessionManager.session(id: context.sessionID)
		await bindBearerTokenIfNeeded(token, to: context.sessionID)
		_ = await session.work { _ in await self.processInbound(messages) }

		// Modern is sessionless: reclaim the ephemeral session immediately (a
		// notification-only request opens no stream, so nothing else would).
		if context.isModern {
			await sessionManager.removeSession(id: context.sessionID)
		}

		let ackHeaders: HTTPFields = context.isModern ? [:] : [.mcpSessionID: sid]
		return RouteResponse(status: .accepted, headerFields: ackHeaders)
	}

	/// Process an inbound HTTP payload: through the connected ``MCPDispatcher``
	/// (decoupled mode, where the gate lives) or the transport's own server
	/// (server-coupled mode, gated upstream at the HTTP layer). Bind the session
	/// (and any request-stream scope) before calling.
	internal func processInbound(_ messages: [JSONRPCMessage]) async -> [JSONRPCMessage] {
		if let dispatcher = self.dispatcher {
			if messages.count == 1 {
				if let reply = await dispatcher.handle(messages[0]) {
					return [reply]
				}
				return []
			}
			return await dispatcher.handle(messages)
		}
		return await self.server?.processBatch(messages, ignoringEmptyResponses: true) ?? []
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
		// DELETE is a session-teardown verb; the modern (sessionless) era has no
		// sessions, so a modern client using it gets 405 Method Not Allowed.
		if requestDeclaresModern(request) {
			return textResponse(status: .methodNotAllowed, body: "DELETE is not supported for stateless (modern) requests.")
		}

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
