import Foundation

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
