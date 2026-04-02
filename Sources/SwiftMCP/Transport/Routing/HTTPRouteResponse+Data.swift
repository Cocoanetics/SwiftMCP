//
//  HTTPRouteResponse+Data.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 02.04.26.
//

import Foundation

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
