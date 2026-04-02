import Foundation

/// Simple linear-scan HTTP router with path parameter extraction.
final class Router: @unchecked Sendable {

	internal var routes: [HTTPRoute] = []

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

	internal func pathSegments(_ path: String) -> [String] {
		path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
	}

	internal func matchPattern(_ pattern: String, against requestSegments: [String]) -> [String: String]? {
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
