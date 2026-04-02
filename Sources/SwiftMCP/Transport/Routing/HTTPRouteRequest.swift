import Foundation

/// A transport-agnostic HTTP request.
///
/// The `Body` generic parameter determines whether the request body is buffered (`Data?`)
/// or streaming (`AsyncStream<Data>`).
public struct HTTPRouteRequest<Body: Sendable>: Sendable {

	/// The HTTP method.
	public let method: RouteMethod

	/// The raw URI string (path + query string).
	public let uri: String

	/// The path component of the URI (without query string).
	public let path: String

	/// HTTP headers as name-value pairs.
	public let headers: [(String, String)]

	/// The request body — `Data?` for buffered handlers, `AsyncStream<Data>` for streaming handlers.
	public let body: Body

	/// Path parameters extracted from `:segments` in the route pattern.
	/// For example, route `/files/:id` matched against `/files/abc` yields `["id": "abc"]`.
	public let pathParams: [String: String]

	/// Query parameters from the URI. Array of tuples to support duplicate keys.
	/// For example, `?tag=a&tag=b` yields `[("tag", "a"), ("tag", "b")]`.
	public let queryParams: [(String, String)]

	// MARK: - Convenience

	/// Extracts the Bearer token from the Authorization header, if present.
	public var bearerToken: String? {
		guard let auth = header("Authorization") else { return nil }
		let prefix = "Bearer "
		guard auth.hasPrefix(prefix) else { return nil }
		return String(auth.dropFirst(prefix.count))
	}

	/// Extracts the session ID from the `Mcp-Session-Id` header, if present.
	public var sessionID: String? {
		header("Mcp-Session-Id")
	}

	/// Returns the first header value matching the given name (case-insensitive).
	public func header(_ name: String) -> String? {
		headers.first(where: { $0.0.caseInsensitiveCompare(name) == .orderedSame })?.1
	}
}
