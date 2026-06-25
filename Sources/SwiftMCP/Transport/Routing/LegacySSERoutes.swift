#if Server
import Foundation
import HTTPTypes

/// Legacy SSE protocol routes (`/sse`, `/messages/:sessionID`).
extension HTTPSSETransport {

	/// Returns the legacy SSE protocol routes.
	func legacySSERoutes() -> [HTTPRoute] {
		[
			// GET /sse — SSE connection (legacy protocol)
			HTTPRoute(.get, "/sse", calling: HTTPSSETransport.handleSSE),

			// Non-GET on /sse → 405
			HTTPRoute(method: nil, pathPattern: "/sse",
				handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .methodNotAllowed) }),

			// POST /messages/:sessionID — legacy message endpoint
			HTTPRoute(.post, "/messages/:sessionID", calling: HTTPSSETransport.handleMessages),

			// Non-POST on /messages/* → 405
			HTTPRoute(method: nil, pathPattern: "/messages/:sessionID",
				handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .methodNotAllowed) })
		]
	}

	// MARK: - Handler Implementations

	/// Handle POST /messages/:sessionID — legacy message endpoint.
	func handleMessages(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {

		// Extract client ID from URL path
		guard let components = URLComponents(string: request.uri),
			  let idString = components.path.components(separatedBy: "/").last,
			  let sessionID = UUID(uuidString: idString),
			  components.path.hasPrefix("/messages/") else {
			logger.warning("Invalid message endpoint URL format: \(request.uri)")
			return RouteResponse(status: .badRequest)
		}

		guard await sessionManager.hasSession(id: sessionID) else {
			logger.warning("Rejected message for unknown legacy SSE session \(sessionID)")
			return textResponse(status: .notFound, body: "Unknown session. Connect to /sse first.")
		}

		// Check authorization
		let token = request.bearerToken

		let authResult = await authorize(token, sessionID: sessionID)
		switch authResult {
		case .unauthorized(let message):
			let err = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: "Unauthorized: \(message)"))
			return RouteResponse.json(err, status: .unauthorized, sessionId: sessionID.uuidString)
		case .jweNotSupported(let message):
			let err = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32000, message: message))
			return RouteResponse.json(err, status: .forbidden, sessionId: sessionID.uuidString)
		case .authorized:
			break
		}

		guard let body = request.body else {
			return RouteResponse(status: .badRequest)
		}

		do {
			let messages = try JSONRPCMessage.decodeMessages(from: body)
			if await sessionNeedsInitialize(sessionID), !SessionInitializationGate.batchStartsWithInitialize(messages) {
				logger.warning("Rejected legacy SSE request for uninitialized session \(sessionID)")
				return textResponse(
					status: .badRequest,
					body: "Session not initialized. Send initialize first.",
					sessionID: sessionID
				)
			}

			// Gate batches by the negotiated version, exactly as `/mcp` does — so a
			// revision that removed batching is rejected on this endpoint too.
			if let batchError = await batchingRejectionResponse(
				body: body,
				request: request,
				messages: messages,
				sessionID: sessionID
			) {
				logger.warning("Rejected legacy SSE batch on a no-batching protocol version (\(sessionID))")
				return batchError
			}

			await dispatchLegacyMessages(messages, sessionID: sessionID)
		} catch {
			logger.error("Failed to decode JSON-RPC message in SSE context: \(error)")
		}

		return RouteResponse(status: .accepted)
	}

	/// Dispatch decoded legacy-SSE messages. Replies are delivered asynchronously
	/// on the session's general SSE stream (the POST itself returns `202`).
	///
	/// The general stream is bound as the outbound scope for the duration of
	/// dispatch, so a tool's mid-call notifications land there too. Dispatch goes
	/// through the connected ``MCPDispatcher`` (decoupled mode) or the transport's
	/// own server (server-coupled mode) via ``processInbound(_:)``.
	private func dispatchLegacyMessages(_ messages: [JSONRPCMessage], sessionID: UUID) async {
		let session = await sessionManager.session(id: sessionID)
		let generalStreamContext = await sessionManager.primaryGeneralStreamID(for: sessionID)
			.map { OutboundStreamContext(streamID: $0, kind: .general) }

		let responses: [JSONRPCMessage]
		if let generalStreamContext {
			responses = await session.work(onStream: generalStreamContext) { _ in
				await self.processInbound(messages)
			}
		} else {
			responses = await session.work { _ in await self.processInbound(messages) }
		}

		if let generalStreamID = generalStreamContext?.streamID {
			for response in responses {
				_ = try? await self.sendJSONRPC(response, to: generalStreamID)
			}
		}
	}

	// MARK: - Helpers

	/// Construct the endpoint URL for the legacy SSE protocol.
	func endpointUrl(from request: HTTPRouteRequest<Data?>, sessionID: UUID) -> URL? {
		var components = URLComponents()

		if let host = request.header("Host") {
			components.host = host
		} else if let remoteAddress = request.header("X-Forwarded-Host") {
			components.host = remoteAddress
		} else {
			components.host = self.host
		}

		if let proto = request.header("X-Forwarded-Proto") {
			components.scheme = proto
		} else {
			components.scheme = "http"
		}

		if let port = request.header("X-Forwarded-Port") {
			components.port = Int(port)
		} else if let host = components.host, host.contains(":") {
			let parts = host.split(separator: ":")
			components.host = String(parts[0])
			components.port = Int(parts[1])
		} else {
			components.port = self.port
		}

		components.path = "/messages/\(sessionID.uuidString)"

		if components.port == 80, components.scheme == "http" {
			components.port = nil
		} else if components.port == 443, components.scheme == "https" {
			components.port = nil
		}

		return components.url
	}
}
#endif
