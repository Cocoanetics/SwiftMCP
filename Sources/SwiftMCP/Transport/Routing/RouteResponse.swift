#if Server
import Foundation
import HTTPTypes

/// Internal response type that can carry either buffered data or a stream.
struct RouteResponse: Sendable {
	var status: HTTPResponse.Status
	var headerFields: HTTPFields
	var body: Data?
	var bodyStream: AsyncStream<Data>?
	/// Optional stream registration info used to register SSE channels.
	var streamInfo: StreamRouteResponseInfo?

	init(status: HTTPResponse.Status, headerFields: HTTPFields = [:], body: Data? = nil) {
		self.status = status
		self.headerFields = headerFields
		self.body = body
		self.bodyStream = nil
		self.streamInfo = nil
	}

	init(
		status: HTTPResponse.Status,
		headerFields: HTTPFields = [:],
		bodyStream: AsyncStream<Data>,
		streamInfo: StreamRouteResponseInfo? = nil
	) {
		self.status = status
		self.headerFields = headerFields
		self.body = nil
		self.bodyStream = bodyStream
		self.streamInfo = streamInfo
	}

	init(_ response: HTTPRouteResponse<Data?>) {
		self.status = response.status
		self.headerFields = response.headerFields
		self.body = response.body
		self.bodyStream = nil
		self.streamInfo = nil
	}

	init(_ response: HTTPRouteResponse<AsyncStream<Data>>) {
		self.status = response.status
		self.headerFields = response.headerFields
		self.body = nil
		self.bodyStream = response.body
		self.streamInfo = nil
	}

	static func json<T: Encodable>(
		_ value: T,
		status: HTTPResponse.Status = .ok,
		sessionId: String? = nil
	) -> RouteResponse {
		let encoder = JSONRPCMessage.makeEncoder()
		encoder.nonConformingFloatEncodingStrategy = .convertToString(
			positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
		guard let data = try? encoder.encode(value) else {
			return RouteResponse(status: .internalServerError, body: Data("Internal Server Error encoding response".utf8))
		}
		var headerFields: HTTPFields = [.contentType: "application/json"]
		if let sessionId {
			headerFields[.mcpSessionID] = sessionId
		}
		return RouteResponse(status: status, headerFields: headerFields, body: data)
	}
}
#endif
