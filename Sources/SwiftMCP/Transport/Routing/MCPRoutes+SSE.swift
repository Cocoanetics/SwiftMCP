#if Server
import Foundation
import HTTPTypes

extension HTTPSSETransport {
	/// Resolved request context used by `handleSSE`.
	fileprivate struct SSEContext {
		let sessionID: UUID
		let authSessionID: UUID?
		let isLegacy: Bool
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

		let resolved = resolveSSESession(sessionHeader: sessionHeader, isLegacy: isLegacy)
		switch resolved {
		case .response(let response):
			return response
		case .context(let context):
			do {
				return try await dispatchSSEConnection(request: request, context: context)
			} catch let error as SSEStreamCreationError {
				return mapStreamCreationError(error, sessionID: context.sessionID)
			}
		}
	}

	/// Map a stream-creation error to the appropriate HTTP response.
	fileprivate func mapStreamCreationError(_ error: SSEStreamCreationError, sessionID: UUID) -> RouteResponse {
		switch error {
		case .malformedLastEventID:
			return textResponse(status: .badRequest, body: "Malformed Last-Event-ID header.", sessionID: sessionID)
		case .unknownStream:
			return textResponse(status: .notFound, body: "Unknown or expired resumable stream.", sessionID: sessionID)
		case .internalError:
			return textResponse(status: .internalServerError, body: "Failed to resume stream.", sessionID: sessionID)
		}
	}

	/// Outcome of resolving an SSE request's session header — either a response to return early,
	/// or a fully-formed SSE context.
	fileprivate enum SSEResolution {
		case response(RouteResponse)
		case context(SSEContext)
	}

	/// Resolve the session header for an SSE request, returning either an error response or a context.
	fileprivate func resolveSSESession(
		sessionHeader: SessionHeaderResolution,
		isLegacy: Bool
	) -> SSEResolution {
		switch sessionHeader {
		case .missing:
			if isLegacy {
				return .context(SSEContext(sessionID: UUID(), authSessionID: nil, isLegacy: true))
			}
			return .response(textResponse(status: .badRequest, body: "Missing Mcp-Session-Id. Send initialize first."))
		case .existing(let existingSessionID):
			return .context(SSEContext(
				sessionID: existingSessionID,
				authSessionID: existingSessionID,
				isLegacy: isLegacy
			))
		case .malformed:
			return .response(textResponse(status: .badRequest, body: "Invalid Mcp-Session-Id header."))
		case .unknown:
			return .response(textResponse(status: .notFound, body: "Unknown session. Send initialize first."))
		}
	}

	/// Authorize and open the SSE stream for the resolved context.
	fileprivate func dispatchSSEConnection(
		request: HTTPRouteRequest<Data?>,
		context: SSEContext
	) async throws -> RouteResponse {
		if let errorResponse = await validateHTTPProtocolVersion(for: request, sessionID: context.authSessionID) {
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
			- Client/Session ID: \(context.sessionID)
			- User-Agent: \(userAgent)
			- Accept: \(acceptHeader)
			- Protocol: \(context.isLegacy ? "Old (HTTP+SSE)" : "New (Streamable HTTP)")
			""")

		let token = request.bearerToken

		if let authError = await authorizeSSE(token: token, authSessionID: context.authSessionID) {
			return authError
		}

		await bindBearerTokenIfNeeded(token, to: context.sessionID)

		let (stream, streamInfo) = try await createSSEStreamForContext(request: request, context: context)
		if context.isLegacy {
			if let endpointResponse = handleLegacyEndpoint(request: request, sessionID: context.sessionID) {
				return endpointResponse
			}
		}

		logger.info("SSE connection setup complete for client \(context.sessionID)")

		return makeSSEResponse(stream: stream, streamInfo: streamInfo, context: context)
	}

	/// Authorize an SSE request and return an error response if authorization fails.
	fileprivate func authorizeSSE(token: String?, authSessionID: UUID?) async -> RouteResponse? {
		switch await authorize(token, sessionID: authSessionID) {
		case .unauthorized(let message):
			logger.warning("Unauthorized SSE connect: \(message)")
			return RouteResponse(status: .unauthorized)
		case .jweNotSupported(let message):
			logger.warning("JWE token not supported for SSE connect: \(message)")
			return RouteResponse(status: .forbidden)
		case .authorized:
			return nil
		}
	}

	/// Create or resume an SSE stream for the request context.
	fileprivate func createSSEStreamForContext(
		request: HTTPRouteRequest<Data?>,
		context: SSEContext
	) async throws -> (AsyncStream<Data>, StreamRouteResponseInfo) {
		if context.isLegacy {
			return await createSSEStream(sessionID: context.sessionID, kind: .legacyGeneral)
		}

		if let lastEventID = request.header("Last-Event-ID") ?? request.header("last-event-id") {
			do {
				return try await resumeSSEStream(sessionID: context.sessionID, lastEventID: lastEventID)
			} catch SessionManager.StreamResumeError.malformedEventID {
				throw SSEStreamCreationError.malformedLastEventID
			} catch SessionManager.StreamResumeError.sessionMismatch,
					SessionManager.StreamResumeError.unknownStream,
					SessionManager.StreamResumeError.resumePointUnavailable {
				throw SSEStreamCreationError.unknownStream
			} catch {
				throw SSEStreamCreationError.internalError
			}
		}

		return await createSSEStream(sessionID: context.sessionID, kind: .general)
	}

	/// Send the endpoint event for legacy SSE protocol; returns an early response on failure.
	fileprivate func handleLegacyEndpoint(request: HTTPRouteRequest<Data?>, sessionID: UUID) -> RouteResponse? {
		if let endpointUrl = endpointUrl(from: request, sessionID: sessionID) {
			logger.info("Sending endpoint event with URL: \(endpointUrl)")
			let message = SSEMessage(data: endpointUrl.absoluteString, eventName: "endpoint")
			sendSSE(message, to: sessionID)
			return nil
		}
		logger.error("Failed to construct endpoint URL")
		return RouteResponse(status: .internalServerError)
	}

	/// Build the final SSE route response from the stream and context.
	fileprivate func makeSSEResponse(
		stream: AsyncStream<Data>,
		streamInfo: StreamRouteResponseInfo,
		context: SSEContext
	) -> RouteResponse {
		var headerFields: HTTPFields = [
			.contentType: "text/event-stream",
			.cacheControl: "no-cache",
			.connection: "keep-alive",
			.accessControlAllowMethods: "GET",
			.accessControlAllowHeaders: "Content-Type, Authorization, MCP-Protocol-Version"
		]

		if !context.isLegacy {
			headerFields[.mcpSessionID] = context.sessionID.uuidString
		}

		return RouteResponse(status: .ok, headerFields: headerFields, bodyStream: stream, streamInfo: streamInfo)
	}

	fileprivate enum SSEStreamCreationError: Error {
		case malformedLastEventID
		case unknownStream
		case internalError
	}
}
#endif
