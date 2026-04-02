import Foundation

/// Result of a successful route match.
struct RouteMatch: Sendable {
	let route: HTTPRoute
	let pathParams: [String: String]
}
