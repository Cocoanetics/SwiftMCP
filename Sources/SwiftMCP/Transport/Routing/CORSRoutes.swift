#if Server
import Foundation
import HTTPTypes

/// CORS preflight route handler.
extension HTTPSSETransport {

	/// Returns the CORS preflight route (`OPTIONS *`).
	func corsRoutes() -> [HTTPRoute] {
		[
			HTTPRoute(
				method: .options,
				pathPattern: "/*",
				handler: { (_: HTTPSSETransport, _: HTTPRouteRequest<Data?>) in
					RouteResponse(status: .ok, headerFields: [
						.accessControlAllowMethods: "GET, POST, DELETE, OPTIONS",
						.accessControlAllowHeaders:
							"Content-Type, Content-Disposition, Authorization, "
								+ "MCP-Protocol-Version, Mcp-Session-Id"
					])
				}
			)
		]
	}
}
#endif
