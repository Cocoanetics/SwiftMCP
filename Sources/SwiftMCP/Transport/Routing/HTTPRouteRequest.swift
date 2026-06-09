#if Server
import Foundation
import HTTPTypes

/// A transport-agnostic HTTP request.
///
/// The `Body` generic parameter determines whether the request body is buffered (`Data?`)
/// or streaming (`AsyncStream<Data>`).
public struct HTTPRouteRequest<Body: Sendable>: Sendable {

	/// The HTTP method.
	public let method: HTTPRequest.Method

	/// The raw URI string (path + query string).
	public let uri: String

	/// The path component of the URI (without query string).
	public let path: String

	/// HTTP header fields. Case-insensitive and validated (see `HTTPTypes.HTTPFields`).
	public let headerFields: HTTPFields

	/// The request body — `Data?` for buffered handlers, `AsyncStream<Data>` for streaming handlers.
	public let body: Body

	/// Path parameters extracted from `:segments` in the route pattern.
	/// For example, route `/files/:id` matched against `/files/abc` yields `["id": "abc"]`.
	public let pathParams: [String: String]

	/// Query parameters from the URI. Array of tuples to support duplicate keys.
	/// For example, `?tag=a&tag=b` yields `[("tag", "a"), ("tag", "b")]`.
	public let queryParams: [(String, String)]

	public init(
		method: HTTPRequest.Method,
		uri: String,
		path: String,
		headerFields: HTTPFields,
		body: Body,
		pathParams: [String: String],
		queryParams: [(String, String)]
	) {
		self.method = method
		self.uri = uri
		self.path = path
		self.headerFields = headerFields
		self.body = body
		self.pathParams = pathParams
		self.queryParams = queryParams
	}

	// MARK: - Convenience

	/// Extracts the Bearer token from the Authorization header, if present.
	public var bearerToken: String? {
		guard let auth = headerFields[.authorization] else { return nil }
		let prefix = "Bearer "
		guard auth.hasPrefix(prefix) else { return nil }
		return String(auth.dropFirst(prefix.count))
	}

	/// Extracts the session ID from the `Mcp-Session-Id` header, if present.
	public var sessionID: String? {
		headerFields[.mcpSessionID]
	}

	/// Returns the first header value matching the given name (case-insensitive).
	///
	/// Returns `nil` if `name` is not a valid HTTP field token or the field is absent.
	public func header(_ name: String) -> String? {
		guard let fieldName = HTTPField.Name(name) else { return nil }
		return headerFields[fieldName]
	}

	/// HTTP headers as name-value pairs.
	@available(*, deprecated, message: "Use headerFields (HTTPFields) instead.")
	public var headers: [(String, String)] {
		headerFields.legacyPairs
	}
}
#endif
