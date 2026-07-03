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

	/// The full modern pre-dispatch gate, in order: batch-framing rejection
	/// (`400` + `-32600`), required-header validation (`400` + `-32001`), then the
	/// unknown-method check (`404` + `-32601`). All must be decided *before*
	/// dispatch — the per-request SSE stream commits the HTTP status, so an
	/// in-band error can't produce the spec-required codes.
	func modernPreflightResponse<Body: Sendable>(
		request: HTTPRouteRequest<Body>,
		body: Data,
		messages: [JSONRPCMessage]
	) -> RouteResponse? {
		// Modern forbids JSON-RPC batching, so a top-level array — even with a
		// single element (which still classifies as modern) — is malformed
		// *framing*. It must be rejected here, first, or the header validation /
		// unknown-method checks below would mask the required -32600.
		if JSONRPCMessage.batchingRejected(body: body, version: MCPProtocolVersion.modern) {
			let error = JSONRPCMessage.batchingRejectionResponse(version: MCPProtocolVersion.modern)
			return .json(error, status: .badRequest, sessionId: nil)
		}
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

		// `Mcp-Param-{name}` headers mirror `tools/call` arguments (`x-mcp-header`);
		// every *present* one must equal the body argument. Presence is not
		// required — the server obligation is header==body, and requiring annotated
		// params to be mirrored would need tool metadata pre-dispatch. Requests
		// only: a notification gets no error response, so there is nothing coherent
		// to reject it with (matching the unknown-method check's scoping).
		if message.isRequest, message.method == "tools/call",
		   let paramError = validateMirroredParamHeaders(request: request, message: message) {
			return paramError
		}

		return nil
	}

	/// Validates every `Mcp-Param-{name}` header against the corresponding
	/// `tools/call` argument. The parameter-name match is case-insensitive (HTTP
	/// header names are case-insensitive and proxies may re-case them); a header
	/// naming no argument, a malformed base64 sentinel, or a value that doesn't
	/// equal the stringified argument is a mismatch.
	private func validateMirroredParamHeaders<Body: Sendable>(
		request: HTTPRouteRequest<Body>,
		message: JSONRPCMessage
	) -> RouteResponse? {
		let arguments = message.params?["arguments"]?.dictionaryValue ?? [:]

		let prefix = "mcp-param-"
		for field in request.headerFields where field.name.rawName.lowercased().hasPrefix(prefix) {
			let paramName = String(field.name.rawName.dropFirst(prefix.count))
			guard let argument = Self.matchedArgument(named: paramName, in: arguments),
			      let headerValue = Self.decodedParamHeaderValue(field.value),
			      headerValue == Self.stringifiedArgument(argument) else {
				return headerMismatchResponse(id: message.id, field: field.name.rawName)
			}
		}
		return nil
	}

	/// The argument a `Mcp-Param-{name}` header refers to: an exact-name match
	/// wins; otherwise a case-insensitive match is accepted only when it is
	/// unambiguous (proxies may re-case header names, but two arguments differing
	/// only by case must not resolve nondeterministically — ambiguity rejects).
	private static func matchedArgument(named name: String, in arguments: JSONDictionary) -> JSONValue? {
		if let exact = arguments[name] {
			return exact
		}
		let lowercased = name.lowercased()
		let candidates = arguments.filter { $0.key.lowercased() == lowercased }
		return candidates.count == 1 ? candidates.first?.value : nil
	}

	/// Decodes an `Mcp-Param-*` header value: a `=?base64?…?=` sentinel wraps
	/// non-ASCII values and is decoded to UTF-8; anything else is taken verbatim.
	/// Returns `nil` for a malformed sentinel (invalid base64 or non-UTF-8 bytes).
	private static func decodedParamHeaderValue(_ value: String) -> String? {
		guard value.hasPrefix("=?base64?"), value.hasSuffix("?=") else {
			return value
		}
		let encoded = String(value.dropFirst("=?base64?".count).dropLast("?=".count))
		guard let data = Data(base64Encoded: encoded) else {
			return nil
		}
		return String(bytes: data, encoding: .utf8)
	}

	/// The string form of a `tools/call` argument a mirroring header must carry:
	/// strings verbatim, everything else as its compact JSON text (`42`, `true`).
	/// Keys are sorted so object-valued arguments have a deterministic text form —
	/// without it, dictionary-order nondeterminism would randomly reject a
	/// correctly mirrored object parameter.
	private static func stringifiedArgument(_ value: JSONValue) -> String? {
		if let string = value.stringValue {
			return string
		}
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.sortedKeys]
		guard let data = try? encoder.encode(value) else {
			return nil
		}
		return String(bytes: data, encoding: .utf8)
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
