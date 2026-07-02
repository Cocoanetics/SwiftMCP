#if Server
import Foundation
import HTTPTypes

/// Modern (`2026-07-28`) required-header validation.
///
/// A modern POST carries redundant headers that duplicate parts of the JSON-RPC
/// body so intermediaries can route/inspect without parsing it. The server MUST
/// validate them against the body and reject a mismatch with `HeaderMismatch`
/// (JSON-RPC code `-32001`, HTTP `400`). Legacy requests are unaffected — this is
/// only invoked for requests classified modern by their body `_meta`.
extension HTTPSSETransport {

	/// The full modern pre-dispatch gate: required-header validation (`400` +
	/// `-32001`) and the unknown-method check (`404` + `-32601`), in that order.
	/// Both must be decided *before* dispatch — the per-request SSE stream commits
	/// the HTTP status, so an in-band error can't produce the spec-required codes.
	func modernPreflightResponse<Body: Sendable>(
		request: HTTPRouteRequest<Body>,
		messages: [JSONRPCMessage]
	) -> RouteResponse? {
		if let headerError = validateModernHeaders(request: request, messages: messages) {
			return headerError
		}
		return modernUnknownMethodResponse(messages: messages)
	}

	/// A `404` + `-32601` for a modern *request* whose method is outside the
	/// modern-era surface (``ModernRequestMethods``). Notifications never 404
	/// (they get a `202` as usual); legacy keeps its in-band `-32601` over `200`.
	private func modernUnknownMethodResponse(messages: [JSONRPCMessage]) -> RouteResponse? {
		guard let message = messages.first, message.isRequest,
		      let method = message.method, !ModernRequestMethods.known.contains(method) else {
			return nil
		}
		let error = JSONRPCMessage.errorResponse(
			id: message.id,
			error: .init(code: -32601, message: "Method not found: \(method)")
		)
		return .json(error, status: .notFound, sessionId: nil)
	}

	/// Validates the modern required headers against the decoded message, returning
	/// a `-32001` response on the first missing/mismatched header, or `nil` when all
	/// match. Modern is a single message (``SessionInitializationGate/batchIsModern``
	/// requires a lone payload), so only the leading message is checked.
	func validateModernHeaders<Body: Sendable>(
		request: HTTPRouteRequest<Body>,
		messages: [JSONRPCMessage]
	) -> RouteResponse? {
		guard let message = messages.first else {
			return nil
		}

		// `MCP-Protocol-Version` must be present and equal the `_meta` version.
		let metaVersion = message.params?["_meta"]?[MCPMetaKey.protocolVersion]?.stringValue
		guard let headerVersion = request.header("MCP-Protocol-Version"), headerVersion == metaVersion else {
			return headerMismatchResponse(id: message.id, field: "MCP-Protocol-Version")
		}

		// `Mcp-Method` must be present and equal the JSON-RPC method (requests and
		// notifications).
		guard request.header("Mcp-Method") == message.method else {
			return headerMismatchResponse(id: message.id, field: "Mcp-Method")
		}

		// `Mcp-Name` must equal `params.name` (`tools/call` / `prompts/get`) or
		// `params.uri` (`resources/read`); it is not used by other methods. The
		// header and body field are compared *as optionals*: a header without the
		// body field (or vice versa) is a mismatch — only "both absent" passes,
		// leaving the missing body field to the method handler's own validation. A
		// present-but-non-string body field can never be mirrored by a header, so
		// it is always a mismatch (rather than degrading to "absent" and letting a
		// headerless request slip past validation).
		if let bodyName = mcpNameBodyValue(for: message) {
			guard !bodyName.malformed, request.header("Mcp-Name") == bodyName.value else {
				return headerMismatchResponse(id: message.id, field: "Mcp-Name")
			}
		}

		return nil
	}

	/// The body field `Mcp-Name` mirrors for methods that use it — wrapped so
	/// "method doesn't use `Mcp-Name`" (`nil`) is distinct from "method uses it
	/// but the body field is absent" (`.value == nil`, which still must match an
	/// absent header). `malformed` marks a field that is present but not a string.
	private struct McpNameBodyValue {
		let value: String?
		let malformed: Bool
	}

	private func mcpNameBodyValue(for message: JSONRPCMessage) -> McpNameBodyValue? {
		let rawField: JSONValue?
		switch message.method {
		case "tools/call", "prompts/get":
			rawField = message.params?["name"]
		case "resources/read":
			rawField = message.params?["uri"]
		default:
			return nil
		}
		return McpNameBodyValue(
			value: rawField?.stringValue,
			malformed: rawField != nil && rawField?.stringValue == nil
		)
	}

	private func headerMismatchResponse(id: JSONRPCID?, field: String) -> RouteResponse {
		let error = JSONRPCMessage.errorResponse(
			id: id,
			error: .init(code: -32001, message: "HeaderMismatch: \(field) does not match the request body.")
		)
		return .json(error, status: .badRequest, sessionId: nil)
	}
}
#endif
