#if Server
import Testing
import Foundation
import HTTPTypes
@testable import SwiftMCP

@Suite("Router Path Matching")
struct RouterTests {

	// MARK: - Exact Path Matching

	@Test("matches exact path")
	func exactMatch() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: .get,
			pathPattern: "/health",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		let match = router.match(method: .get, path: "/health")
		#expect(match != nil)
		#expect(match?.pathParams.isEmpty == true)
	}

	@Test("rejects non-matching path")
	func noMatch() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: .get,
			pathPattern: "/health",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		#expect(router.match(method: .get, path: "/status") == nil)
	}

	@Test("rejects wrong method")
	func wrongMethod() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: .get,
			pathPattern: "/health",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		#expect(router.match(method: .post, path: "/health") == nil)
	}

	@Test("nil method matches any")
	func anyMethod() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: nil,
			pathPattern: "/anything",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		#expect(router.match(method: .get, path: "/anything") != nil)
		#expect(router.match(method: .post, path: "/anything") != nil)
		#expect(router.match(method: .delete, path: "/anything") != nil)
	}

	// MARK: - Path Parameters

	@Test("extracts single path parameter")
	func singleParam() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: .get,
			pathPattern: "/files/:id",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		let match = router.match(method: .get, path: "/files/abc123")
		#expect(match != nil)
		#expect(match?.pathParams["id"] == "abc123")
	}

	@Test("extracts multiple path parameters")
	func multipleParams() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: .post,
			pathPattern: "/users/:userId/posts/:postId",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		let match = router.match(method: .post, path: "/users/42/posts/99")
		#expect(match != nil)
		#expect(match?.pathParams["userId"] == "42")
		#expect(match?.pathParams["postId"] == "99")
	}

	@Test("rejects path with too few segments for parameters")
	func tooFewSegments() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: .get,
			pathPattern: "/files/:id",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		#expect(router.match(method: .get, path: "/files") == nil)
	}

	@Test("rejects path with too many segments")
	func tooManySegments() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: .get,
			pathPattern: "/files/:id",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		#expect(router.match(method: .get, path: "/files/abc/extra") == nil)
	}

	// MARK: - Wildcard

	@Test("trailing wildcard matches any suffix")
	func trailingWildcard() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: nil,
			pathPattern: "/oauth/*",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		#expect(router.match(method: .get, path: "/oauth/token") != nil)
		#expect(router.match(method: .post, path: "/oauth/register") != nil)
		#expect(router.match(method: .get, path: "/oauth/a/b/c") != nil)
		#expect(router.match(method: .get, path: "/oauth") != nil)
	}

	@Test("wildcard does not match different prefix")
	func wildcardWrongPrefix() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: nil,
			pathPattern: "/oauth/*",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		#expect(router.match(method: .get, path: "/other/token") == nil)
	}

	// MARK: - First Match Wins

	@Test("first match wins")
	func firstMatchWins() {
		let router = Router()

		// More specific route first
		router.addRoute(HTTPRoute(
			method: .get,
			pathPattern: "/mcp",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in
				RouteResponse(status: .ok, body: Data("specific".utf8))
			}
		))

		// Catch-all second
		router.addRoute(HTTPRoute(
			method: .get,
			pathPattern: "/:anything",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in
				RouteResponse(status: .ok, body: Data("catchall".utf8))
			}
		))

		let match = router.match(method: .get, path: "/mcp")
		#expect(match != nil)
		// First route should match (exact before parameter)
		#expect(match?.pathParams.isEmpty == true)
	}

	// MARK: - Mixed literal and parameter segments

	@Test("matches mixed literal and parameter segments")
	func mixedSegments() {
		let router = Router()
		router.addRoute(HTTPRoute(
			method: .post,
			pathPattern: "/mcp/uploads/:cid",
			handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in RouteResponse(status: .ok) }
		))

		let match = router.match(method: .post, path: "/mcp/uploads/content-id-123")
		#expect(match != nil)
		#expect(match?.pathParams["cid"] == "content-id-123")

		// Wrong literal segment
		#expect(router.match(method: .post, path: "/mcp/downloads/abc") == nil)
	}
}
#endif
