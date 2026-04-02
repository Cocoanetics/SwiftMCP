import Foundation

/// Internal response type that can carry either buffered data or a stream.
struct RouteResponse: Sendable {
	var status: HTTPStatus
	var headers: [(String, String)]
	var body: Data?
	var bodyStream: AsyncStream<Data>?
	/// Optional SSE session identifier used to register streaming channels.
	var streamSessionID: UUID?

	init(status: HTTPStatus, headers: [(String, String)] = [], body: Data? = nil) {
		self.status = status
		self.headers = headers
		self.body = body
		self.bodyStream = nil
		self.streamSessionID = nil
	}

	init(status: HTTPStatus, headers: [(String, String)] = [], bodyStream: AsyncStream<Data>, streamSessionID: UUID? = nil) {
		self.status = status
		self.headers = headers
		self.body = nil
		self.bodyStream = bodyStream
		self.streamSessionID = streamSessionID
	}

	init(_ response: HTTPRouteResponse<Data?>) {
		self.status = response.status
		self.headers = response.headers
		self.body = response.body
		self.bodyStream = nil
		self.streamSessionID = nil
	}

	init(_ response: HTTPRouteResponse<AsyncStream<Data>>) {
		self.status = response.status
		self.headers = response.headers
		self.body = nil
		self.bodyStream = response.body
		self.streamSessionID = nil
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
