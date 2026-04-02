import Foundation


/// Protocol for types that can serve as the body of an `HTTPRouteRequest`.
///
/// Conforming types define how to prepare the body from a raw `AsyncStream<Data>`:
/// - `Data?` collects the stream into buffered data.
/// - `AsyncStream<Data>` forwards the stream as-is.
protocol RouteBody: Sendable {
	/// Prepare the body value from the raw body chunk stream.
	static func collect(from stream: AsyncStream<Data>) async -> Self
}


extension Optional: RouteBody where Wrapped == Data {
	/// Collect all chunks into a single `Data?` value.
	static func collect(from stream: AsyncStream<Data>) async -> Data? {
		var collected = Data()
		for await chunk in stream {
			collected.append(chunk)
		}
		return collected.isEmpty ? nil : collected
	}
}


extension AsyncStream<Data>: RouteBody {
	/// Forward the stream as-is — no buffering.
	static func collect(from stream: AsyncStream<Data>) async -> AsyncStream<Data> {
		stream
	}
}


/// A route definition for the HTTP router.
struct HTTPRoute: Sendable {

	/// The HTTP method to match, or `nil` to match any method.
	let method: RouteMethod?

	/// The path pattern, e.g. `/mcp/uploads/:cid` or `/oauth/*`.
	let pathPattern: String

	/// The handler — always receives the raw body stream internally.
	/// The init wraps it to collect or forward based on the handler's body type.
	let handler: @Sendable (HTTPSSETransport, HTTPRouteRequest<AsyncStream<Data>>) async throws -> RouteResponse

	/// Create a route with a closure handler.
	///
	/// The `Body` type is inferred from the handler's request type:
	/// - `Data?` → body stream is collected before the handler is called.
	/// - `AsyncStream<Data>` → body stream is forwarded directly.
	init<Body: RouteBody>(method: RouteMethod?, pathPattern: String,
		 handler: @escaping @Sendable (HTTPSSETransport, HTTPRouteRequest<Body>) async throws -> RouteResponse) {
		self.method = method
		self.pathPattern = pathPattern
		self.handler = { transport, streamingRequest in
			let body = await Body.collect(from: streamingRequest.body)
			let request = HTTPRouteRequest<Body>(
				method: streamingRequest.method, uri: streamingRequest.uri, path: streamingRequest.path,
				headers: streamingRequest.headers, body: body,
				pathParams: streamingRequest.pathParams, queryParams: streamingRequest.queryParams
			)
			return try await handler(transport, request)
		}
	}

	/// Create a route from an unbound instance method reference.
	///
	/// Usage:
	/// ```
	/// HTTPRoute(.POST, "/mcp", calling: HTTPSSETransport.handleStreamableHTTP)
	/// HTTPRoute(.POST, "/upload", calling: HTTPSSETransport.handleUpload)
	/// ```
	init<Body: RouteBody>(_ method: RouteMethod, _ pathPattern: String,
		 calling: @escaping @Sendable (HTTPSSETransport) -> @Sendable (HTTPRouteRequest<Body>) async throws -> RouteResponse) {
		self.init(method: method, pathPattern: pathPattern, handler: { transport, request in
			try await calling(transport)(request)
		})
	}
}


/// Internal response type that can carry either buffered data or a stream.
struct RouteResponse: Sendable {
	var status: HTTPStatus
	var headers: [(String, String)]
	var body: Data?
	var bodyStream: AsyncStream<Data>?

	init(status: HTTPStatus, headers: [(String, String)] = [], body: Data? = nil) {
		self.status = status
		self.headers = headers
		self.body = body
		self.bodyStream = nil
	}

	init(status: HTTPStatus, headers: [(String, String)] = [], bodyStream: AsyncStream<Data>) {
		self.status = status
		self.headers = headers
		self.body = nil
		self.bodyStream = bodyStream
	}

	init(_ response: HTTPRouteResponse<Data?>) {
		self.status = response.status
		self.headers = response.headers
		self.body = response.body
		self.bodyStream = nil
	}

	init(_ response: HTTPRouteResponse<AsyncStream<Data>>) {
		self.status = response.status
		self.headers = response.headers
		self.body = nil
		self.bodyStream = response.body
	}

	static func json<T: Encodable>(_ value: T, status: HTTPStatus = .ok, sessionId: String? = nil) -> RouteResponse {
		let encoder = JSONEncoder()
		encoder.dateEncodingStrategy = .iso8601WithTimeZone
		encoder.nonConformingFloatEncodingStrategy = .convertToString(
			positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
		guard let data = try? encoder.encode(value) else {
			return RouteResponse(status: .internalServerError, body: Data("Internal Server Error encoding response".utf8))
		}
		var headers: [(String, String)] = [("Content-Type", "application/json")]
		if let sessionId {
			headers.append(("Mcp-Session-Id", sessionId))
		}
		return RouteResponse(status: status, headers: headers, body: data)
	}
}


/// Result of a successful route match.
struct RouteMatch: Sendable {
	let route: HTTPRoute
	let pathParams: [String: String]
}


/// Simple linear-scan HTTP router with path parameter extraction.
final class Router: @unchecked Sendable {

	private var routes: [HTTPRoute] = []

	init() {}

	func addRoute(_ route: HTTPRoute) {
		routes.append(route)
	}

	func addRoutes(_ newRoutes: [HTTPRoute]) {
		routes.append(contentsOf: newRoutes)
	}

	func match(method: RouteMethod, path: String) -> RouteMatch? {
		let requestSegments = pathSegments(path)

		for route in routes {
			if let routeMethod = route.method, routeMethod != method {
				continue
			}

			if let params = matchPattern(route.pathPattern, against: requestSegments) {
				return RouteMatch(route: route, pathParams: params)
			}
		}

		return nil
	}

	// MARK: - Path Matching

	private func pathSegments(_ path: String) -> [String] {
		path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
	}

	private func matchPattern(_ pattern: String, against requestSegments: [String]) -> [String: String]? {
		let patternSegments = pathSegments(pattern)
		var params: [String: String] = [:]
		var i = 0

		for (index, segment) in patternSegments.enumerated() {
			if segment == "*" {
				if index == patternSegments.count - 1 {
					return params
				}
				return nil
			}

			guard i < requestSegments.count else {
				return nil
			}

			if segment.hasPrefix(":") {
				let paramName = String(segment.dropFirst())
				params[paramName] = requestSegments[i]
			} else {
				guard segment == requestSegments[i] else {
					return nil
				}
			}

			i += 1
		}

		guard i == requestSegments.count else {
			return nil
		}

		return params
	}
}
