import Foundation


/// CORS preflight route handler.
extension HTTPSSETransport {

	/// Returns the CORS preflight route (`OPTIONS *`).
	func corsRoutes() -> [HTTPRoute] {
		[
			HTTPRoute(
				method: .OPTIONS,
				pathPattern: "/*",
				handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in
					RouteResponse(status: .ok, headers: [
						("Access-Control-Allow-Methods", "GET, POST, DELETE, OPTIONS"),
						("Access-Control-Allow-Headers", "Content-Type, Content-Disposition, Authorization, MCP-Protocol-Version, Mcp-Session-Id"),
					])
				}
			)
		]
	}
}
