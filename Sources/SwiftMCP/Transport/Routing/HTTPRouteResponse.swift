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


// MARK: - Factories for Data? body

extension HTTPRouteResponse where Body == Data? {

	/// 200 OK with raw data body and specified content type.
	public static func ok(_ body: Data, contentType: String) -> Self {
		HTTPRouteResponse(status: .ok, headers: [("Content-Type", contentType)], body: body)
	}

	/// Text response with specified status.
	public static func text(_ string: String, status: HTTPStatus = .ok) -> Self {
		let data = Data(string.utf8)
		return HTTPRouteResponse(status: status, headers: [("Content-Type", "text/plain; charset=utf-8")], body: data)
	}

	/// JSON data response with specified status.
	public static func json(_ data: Data, status: HTTPStatus = .ok) -> Self {
		HTTPRouteResponse(status: status, headers: [("Content-Type", "application/json")], body: data)
	}

	/// 404 Not Found with no body.
	public static var notFound: Self {
		HTTPRouteResponse(status: .notFound, body: nil)
	}

	/// 400 Bad Request with message body.
	public static func badRequest(_ message: String) -> Self {
		.text(message, status: .badRequest)
	}

	/// 405 Method Not Allowed with no body.
	public static var methodNotAllowed: Self {
		HTTPRouteResponse(status: .methodNotAllowed, body: nil)
	}

	/// 401 Unauthorized with message body.
	public static func unauthorized(_ message: String) -> Self {
		.text(message, status: .unauthorized)
	}

	/// 202 Accepted with no body.
	public static var accepted: Self {
		HTTPRouteResponse(status: .accepted, body: nil)
	}
}


// MARK: - Factories for AsyncStream<Data> body

extension HTTPRouteResponse where Body == AsyncStream<Data> {

	/// Stream a file from disk in chunks.
	public static func file(_ url: URL, contentType: String, chunkSize: Int = 65536) -> Self {
		let (stream, continuation) = AsyncStream<Data>.makeStream()

		// Read the file in a background task
		Task {
			defer { continuation.finish() }
			guard let handle = try? FileHandle(forReadingFrom: url) else {
				return
			}
			defer { try? handle.close() }

			while true {
				let chunk = handle.readData(ofLength: chunkSize)
				if chunk.isEmpty { break }
				continuation.yield(chunk)
			}
		}

		return HTTPRouteResponse(
			status: .ok,
			headers: [("Content-Type", contentType)],
			body: stream
		)
	}

	/// Wrap an existing async stream as an event stream response.
	public static func eventStream(_ source: AsyncStream<Data>) -> Self {
		HTTPRouteResponse(
			status: .ok,
			headers: [("Content-Type", "text/event-stream"), ("Cache-Control", "no-cache")],
			body: source
		)
	}
}
