import Foundation

/// A transport-agnostic HTTP response.
///
/// The `Body` generic parameter determines whether the response body is buffered (`Data?`)
/// or streaming (`AsyncStream<Data>`).
public struct HTTPRouteResponse<Body: Sendable>: Sendable {

	/// The HTTP status code.
	public var status: HTTPStatus

	/// Response headers as name-value pairs.
	public var headers: [(String, String)]

	/// The response body.
	public var body: Body

	public init(status: HTTPStatus, headers: [(String, String)] = [], body: Body) {
		self.status = status
		self.headers = headers
		self.body = body
	}
}
