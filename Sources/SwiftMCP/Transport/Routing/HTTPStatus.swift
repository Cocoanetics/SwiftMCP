import Foundation

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
