import SwiftCross

/// OAuth route handlers: authorization server metadata, protected resource metadata,
/// and transparent proxy to Auth0 endpoints.
extension HTTPSSETransport {

	/// Returns the OAuth routes if `oauthConfiguration` is set, otherwise an empty array.
	func oauthRoutes() -> [HTTPRoute] {
		guard oauthConfiguration != nil else { return [] }

		return [
			// GET /.well-known/oauth-authorization-server
			HTTPRoute(.GET, "/.well-known/oauth-authorization-server", calling: HTTPSSETransport.handleOAuthAuthorizationServer),

			// GET /.well-known/oauth-protected-resource
			HTTPRoute(.GET, "/.well-known/oauth-protected-resource", calling: HTTPSSETransport.handleOAuthProtectedResource),

			// GET /.well-known/openid-configuration — local or proxy
			HTTPRoute(method: .GET, pathPattern: "/.well-known/openid-configuration",
				handler: { transport, request in
					if let config = transport.oauthConfiguration, config.transparentProxy {
						return try await transport.handleOAuthProxy(request: request)
					} else {
						return try await transport.handleOAuthAuthorizationServer(request: request)
					}
				}),

			// ANY /authorize — redirect to Auth0
			HTTPRoute(method: nil, pathPattern: "/authorize", handler: { transport, request in
				try await transport.handleOAuthProxy(request: request)
			}),

			// ANY /oauth/* — proxy to Auth0
			HTTPRoute(method: nil, pathPattern: "/oauth/*", handler: { transport, request in
				try await transport.handleOAuthProxy(request: request)
			}),

			// ANY /userinfo
			HTTPRoute(method: nil, pathPattern: "/userinfo", handler: { transport, request in
				try await transport.handleOAuthProxy(request: request)
			}),

			// ANY /.well-known/jwks.json
			HTTPRoute(method: nil, pathPattern: "/.well-known/jwks.json", handler: { transport, request in
				try await transport.handleOAuthProxy(request: request)
			}),

			// ANY /u/* — Auth0 login UI
			HTTPRoute(method: nil, pathPattern: "/u/*", handler: { transport, request in
				try await transport.handleOAuthProxy(request: request)
			})
		]
	}

	// MARK: - Handler Implementations

	/// Serve the OAuth authorization server metadata.
	func handleOAuthAuthorizationServer(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {

		guard let config = oauthConfiguration else {
			return RouteResponse(status: .notFound)
		}

		let metadata: OAuthConfiguration.AuthorizationServerMetadata

		if config.transparentProxy {
			let serverBaseURL = getBaseURL(from: request)
			metadata = config.proxyAuthorizationServerMetadata(serverBaseURL: serverBaseURL)
		} else {
			metadata = config.authorizationServerMetadata()
		}

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		do {
			let data = try encoder.encode(metadata)
			return RouteResponse(status: .ok, headers: [("Content-Type", "application/json")], body: data)
		} catch {
			logger.error("Failed to encode OAuth metadata: \(error)")
			return RouteResponse(status: .internalServerError)
		}
	}

	/// Serve the protected resource metadata.
	func handleOAuthProtectedResource(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {

		guard let config = oauthConfiguration else {
			return RouteResponse(status: .notFound)
		}

		let resourceBaseURL = protectedResourceBaseURL(from: request)

		let metadata: OAuthConfiguration.ProtectedResourceMetadata

		if config.transparentProxy {
			metadata = config.proxyProtectedResourceMetadata(serverBaseURL: resourceBaseURL)
		} else {
			metadata = config.protectedResourceMetadata(resourceBaseURL: resourceBaseURL)
		}

		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

		do {
			let data = try encoder.encode(metadata)
			return RouteResponse(status: .ok, headers: [("Content-Type", "application/json")], body: data)
		} catch {
			logger.error("Failed to encode OAuth metadata: \(error)")
			return RouteResponse(status: .internalServerError)
		}
	}

	/// Build the resource base URL by honoring `X-Forwarded-*` headers when present.
	internal func protectedResourceBaseURL(from request: HTTPRouteRequest<Data?>) -> String {
		let host: String
		if let forwardedHost = request.header("X-Forwarded-Host") {
			host = forwardedHost
		} else if let hostHeader = request.header("Host") {
			host = hostHeader
		} else {
			host = self.host
		}

		let scheme = request.header("X-Forwarded-Proto") ?? "http"

		let port: Int
		if let forwardedPort = request.header("X-Forwarded-Port"), let parsedPort = Int(forwardedPort) {
			port = parsedPort
		} else {
			port = self.port
		}

		var resourceBaseURL = "\(scheme)://\(host)"

		if !(scheme == "http" && port == 80) && !(scheme == "https" && port == 443) {
			if !host.contains(":") {
				resourceBaseURL += ":\(port)"
			}
		}
		return resourceBaseURL
	}

	// MARK: - Helpers

	/// Extract the base URL (scheme + host) from the request headers.
	internal func getBaseURL(from request: HTTPRouteRequest<Data?>) -> String {
		let host: String

		if let forwardedHost = request.header("X-Forwarded-Host") {
			host = forwardedHost
		} else if let hostHeader = request.header("Host") {
			host = hostHeader
		} else {
			host = self.host
		}

		let scheme: String

		if let forwardedProto = request.header("X-Forwarded-Proto") {
			scheme = forwardedProto
		} else {
			scheme = "http"
		}

		return "\(scheme)://\(host)"
	}
}
