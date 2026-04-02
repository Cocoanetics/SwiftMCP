import Foundation


/// HTTP method enum, transport-agnostic (no NIO dependency).
public enum RouteMethod: String, Sendable, CaseIterable {
	case GET, POST, PUT, DELETE, PATCH, OPTIONS, HEAD
}


/// HTTP status code, transport-agnostic (no NIO dependency).
///
/// A struct rather than an enum so that arbitrary status codes (e.g. from
/// proxied upstream responses) can be represented without exhaustive cases.
public struct HTTPStatus: RawRepresentable, Sendable, Equatable {
	public let rawValue: Int

	public init(rawValue: Int) {
		self.rawValue = rawValue
	}

	public static let ok = HTTPStatus(rawValue: 200)
	public static let created = HTTPStatus(rawValue: 201)
	public static let accepted = HTTPStatus(rawValue: 202)
	public static let noContent = HTTPStatus(rawValue: 204)
	public static let movedPermanently = HTTPStatus(rawValue: 301)
	public static let found = HTTPStatus(rawValue: 302)
	public static let badRequest = HTTPStatus(rawValue: 400)
	public static let unauthorized = HTTPStatus(rawValue: 401)
	public static let forbidden = HTTPStatus(rawValue: 403)
	public static let notFound = HTTPStatus(rawValue: 404)
	public static let methodNotAllowed = HTTPStatus(rawValue: 405)
	public static let payloadTooLarge = HTTPStatus(rawValue: 413)
	public static let internalServerError = HTTPStatus(rawValue: 500)
}


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
		guard let auth = header("Authorization") ?? header("authorization") else { return nil }
		let prefix = "Bearer "
		guard auth.hasPrefix(prefix) else { return nil }
		return String(auth.dropFirst(prefix.count))
	}

	/// Extracts the session ID from the `Mcp-Session-Id` header, if present.
	public var sessionID: String? {
		header("Mcp-Session-Id") ?? header("mcp-session-id")
	}

	/// Returns the first header value matching the given name (case-sensitive).
	public func header(_ name: String) -> String? {
		headers.first(where: { $0.0 == name })?.1
	}
}
