import Foundation


/// Legacy SSE protocol routes (`/sse`, `/messages/:sessionID`).
extension HTTPSSETransport {

	/// Returns the legacy SSE protocol routes.
	func legacySSERoutes() -> [HTTPRoute] {
		[
			// GET /sse — SSE connection (legacy protocol)
			HTTPRoute(.GET, "/sse", calling: HTTPSSETransport.handleSSE),

			// Non-GET on /sse → 405
			HTTPRoute(method: nil, pathPattern: "/sse",
				handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .methodNotAllowed) }),

			// POST /messages/:sessionID — legacy message endpoint
			HTTPRoute(.POST, "/messages/:sessionID", calling: HTTPSSETransport.handleMessages),

			// Non-POST on /messages/* → 405
			HTTPRoute(method: nil, pathPattern: "/messages/:sessionID",
				handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .methodNotAllowed) }),
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
			if await sessionNeedsInitialize(sessionID), !batchStartsWithInitialize(messages) {
				logger.warning("Rejected legacy SSE request for uninitialized session \(sessionID)")
				return textResponse(
					status: .badRequest,
					body: "Session not initialized. Send initialize first.",
					sessionID: sessionID
				)
			}

			await sessionManager.session(id: sessionID).work { session in
				for message in messages {
					switch message {
					case .response, .errorResponse:
						await session.handleResponse(message)
					default:
						self.handleJSONRPCRequest(message, from: sessionID)
					}
				}
			}
		} catch {
			logger.error("Failed to decode JSON-RPC message in SSE context: \(error)")
		}

		return RouteResponse(status: .accepted)
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
