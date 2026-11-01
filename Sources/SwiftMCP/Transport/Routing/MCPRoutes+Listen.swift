#if Server
import Foundation
import HTTPTypes

/// Modern `subscriptions/listen`: a POST whose response is a long-lived SSE stream.
/// It replaces the legacy standalone GET stream and `resources/subscribe`, neither of
/// which a modern request may use.
extension HTTPSSETransport {

	/// Open the listen stream: validate the request, then answer with an SSE stream that
	/// starts with `notifications/subscriptions/acknowledged` and stays open until the
	/// client disconnects (or the server stops, which ends it with the empty result).
	func handleSubscriptionsListen(
		_ message: JSONRPCMessage,
		token: String?,
		context: StreamableHTTPContext
	) async -> RouteResponse {
		guard MCPProtocolVersion.profile(for: MCPProtocolVersion.modern)?.has(.subscriptionsListen) == true,
		      let subscriptionID = message.id else {
			return textResponse(status: .notFound, body: "subscriptions/listen is not supported.")
		}

		guard let requested = SubscriptionFilter(message.params?["notifications"]) else {
			let error = JSONRPCMessage.errorResponse(
				id: subscriptionID,
				error: .init(code: -32602, message: "Invalid params: 'notifications' must be a subscription filter object.")
			)
			return .json(error, status: .badRequest, sessionId: nil)
		}

		guard "text/event-stream".matchesAcceptHeader(context.acceptHeader)
			|| "*/*".matchesAcceptHeader(context.acceptHeader) else {
			return textResponse(status: .badRequest, body: "Client must accept text/event-stream.")
		}

		let capabilities = await server?.buildServerCapabilities()
		let session = await admittedSession(for: context)
		await bindBearerTokenIfNeeded(token, to: context.sessionID)
		guard let (stream, streamInfo) = await sessionManager.openListenStream(
			for: session,
			subscriptionID: subscriptionID,
			requested: requested,
			honored: requested.honored(by: capabilities)
		) else {
			return unknownSessionResponse()
		}

		let headerFields: HTTPFields = [
			.contentType: "text/event-stream",
			.cacheControl: "no-cache",
			.connection: "keep-alive",
			.xAccelBuffering: "no"
		]
		return RouteResponse(status: .ok, headerFields: headerFields, bodyStream: stream, streamInfo: streamInfo)
	}
}
#endif
