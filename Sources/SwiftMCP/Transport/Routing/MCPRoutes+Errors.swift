#if Server
import Foundation
import HTTPTypes

extension HTTPSSETransport {

	/// Internal errors thrown while resolving the streamable HTTP context.
	enum StreamableHTTPError: Error {
		case missingSessionForNonInitialize
		case uninitializedSession(UUID)
	}

	/// Build a response describing why JSON-RPC decoding failed.
	func decodeFailureResponse(error: Error, sessionHeader: SessionHeaderResolution) -> RouteResponse {
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
			if case .existing(let session) = sessionHeader {
				return session.id.uuidString
			}
			return nil
		}()
		return .json(response, status: .badRequest, sessionId: sessionID)
	}
}
#endif
