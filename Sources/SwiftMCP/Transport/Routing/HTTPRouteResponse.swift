#if Server
import Foundation
import HTTPTypes

/// A transport-agnostic HTTP response.
///
/// The `Body` generic parameter determines whether the response body is buffered (`Data?`)
/// or streaming (`AsyncStream<Data>`).
public struct HTTPRouteResponse<Body: Sendable>: Sendable {

	/// The HTTP status.
	public var status: HTTPResponse.Status

	/// Response header fields. Case-insensitive and validated (see `HTTPTypes.HTTPFields`).
	public var headerFields: HTTPFields

	/// The response body.
	public var body: Body

	public init(status: HTTPResponse.Status, headerFields: HTTPFields = [:], body: Body) {
		self.status = status
		self.headerFields = headerFields
		self.body = body
	}

	/// Response headers as name-value pairs.
	@available(*, deprecated, message: "Use headerFields (HTTPFields) instead.")
	public init(status: HTTPResponse.Status, headers: [(String, String)], body: Body) {
		self.status = status
		self.headerFields = HTTPFields(legacyPairs: headers)
		self.body = body
	}

	/// Response headers as name-value pairs.
	@available(*, deprecated, message: "Use headerFields (HTTPFields) instead.")
	public var headers: [(String, String)] {
		get { headerFields.legacyPairs }
		set { headerFields = HTTPFields(legacyPairs: newValue) }
	}
}
#endif
