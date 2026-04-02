import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif


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
			}),
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

		let host: String
		let scheme: String
		let port: Int

		if let forwardedHost = request.header("X-Forwarded-Host") {
			host = forwardedHost
		} else if let hostHeader = request.header("Host") {
			host = hostHeader
		} else {
			host = self.host
		}

		if let forwardedProto = request.header("X-Forwarded-Proto") {
			scheme = forwardedProto
		} else {
			scheme = "http"
		}

		if let forwardedPort = request.header("X-Forwarded-Port"), let p = Int(forwardedPort) {
			port = p
		} else {
			port = self.port
		}

		var resourceBaseURL = "\(scheme)://\(host)"

		if !(scheme == "http" && port == 80) && !(scheme == "https" && port == 443) {
			if !host.contains(":") {
				resourceBaseURL += ":\(port)"
			}
		}

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

	/// Handle OAuth proxy requests: /authorize redirects, /oauth/* proxy, /userinfo, jwks, /u/* redirects.
	func handleOAuthProxy(request: HTTPRouteRequest<Data?>) async throws -> RouteResponse {

		logger.info("Handling OAuth proxy request for \(request.uri)")

		guard let config = oauthConfiguration else {
			logger.error("OAuth not configured")
			let err = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32603, message: "OAuth not configured"))
			return .json(err, status: .internalServerError)
		}

		// Handle /authorize — redirect to Auth0 authorization endpoint
		if request.uri.hasPrefix("/authorize") {
			var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!

			if let originalComponents = URLComponents(string: "http://dummy\(request.uri)") {
				components.queryItems = originalComponents.queryItems
			}

			var queryItems = components.queryItems ?? []

			if let audience = config.audience {
				if !queryItems.contains(where: { $0.name == "audience" }) {
					queryItems.append(URLQueryItem(name: "audience", value: audience))
				}
			}

			if !queryItems.contains(where: { $0.name == "scope" && $0.value?.contains("openid") == true }) {
				if let existingScopeIndex = queryItems.firstIndex(where: { $0.name == "scope" }) {
					let existingScope = queryItems[existingScopeIndex].value ?? ""
					let newScope = existingScope.isEmpty ? "openid profile email" : "\(existingScope) openid profile email"
					queryItems[existingScopeIndex] = URLQueryItem(name: "scope", value: newScope)
				} else {
					queryItems.append(URLQueryItem(name: "scope", value: "openid profile email"))
				}
				logger.info("Added openid scope to authorization request")
			}

			components.queryItems = queryItems

			if let redirectURL = components.url {
				logger.info("Redirecting /authorize request to Auth0: \(redirectURL.absoluteString)")
				return RouteResponse(status: .found, headers: [("Location", redirectURL.absoluteString)])
			}
		}

		// Determine the target URL based on the request path
		let targetURL: URL

		switch request.uri {
		case let path where path.hasPrefix("/oauth/token"):
			targetURL = config.tokenEndpoint
		case let path where path.hasPrefix("/oauth/register"):
			targetURL = config.registrationEndpoint ?? config.issuer.appendingPathComponent("oidc/register")
		case let path where path.hasPrefix("/oauth/"):
			let pathComponent = String(request.uri.dropFirst(1))
			targetURL = config.issuer.appendingPathComponent(pathComponent)
		case "/userinfo":
			targetURL = config.issuer.appendingPathComponent("userinfo")
		case "/.well-known/jwks.json":
			targetURL = config.jwksEndpoint ?? config.issuer.appendingPathComponent(".well-known/jwks.json")
		case "/.well-known/openid-configuration":
			targetURL = config.issuer.appendingPathComponent(".well-known/openid-configuration")
		case let path where path.hasPrefix("/u/"):
			let redirectURL = config.issuer.appendingPathComponent(String(request.uri.dropFirst(1))).absoluteString
			logger.info("Redirecting Auth0 UI path to Auth0: \(redirectURL)")
			return RouteResponse(status: .found, headers: [("Location", redirectURL)])
		default:
			logger.error("Unknown OAuth proxy path: \(request.uri)")
			let err = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32601, message: "Unknown OAuth endpoint"))
			return .json(err, status: .notFound)
		}

		// Build the proxy request
		var proxyRequest = URLRequest(url: targetURL)
		proxyRequest.httpMethod = request.method.rawValue

		if let originalComponents = URLComponents(string: "http://dummy\(request.uri)") {
			var targetComponents = URLComponents(url: targetURL, resolvingAgainstBaseURL: false)!
			targetComponents.queryItems = originalComponents.queryItems
			if let finalURL = targetComponents.url {
				proxyRequest.url = finalURL
				logger.info("Proxying to: \(finalURL.absoluteString)")
			}
		}

		// Copy headers, excluding hop-by-hop and forwarding headers
		for (name, value) in request.headers {
			let lowercaseName = name.lowercased()
			if lowercaseName != "host" &&
			   lowercaseName != "content-length" &&
			   lowercaseName != "connection" &&
			   !lowercaseName.hasPrefix("x-forwarded") {
				proxyRequest.setValue(value, forHTTPHeaderField: name)
			}
		}

		if request.uri.hasPrefix("/authorize") || request.uri.hasPrefix("/u/login") {
			proxyRequest.setValue(config.issuer.absoluteString, forHTTPHeaderField: "Referer")
			logger.info("Set Referer header to: \(config.issuer.absoluteString)")
		}

		if let requestBody = request.body {
			proxyRequest.httpBody = requestBody
		}

		do {
			let sessionConfig = URLSessionConfiguration.default
			let delegate = NoRedirectDelegate()
			let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
			let (data, response) = try await session.data(for: proxyRequest)

			guard let httpResponse = response as? HTTPURLResponse else {
				let err = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32603, message: "Invalid response from auth server"))
				return .json(err, status: .internalServerError)
			}

			var responseHeaders: [(String, String)] = []

			// Handle token response: validate and store access token in session
			if request.uri.hasPrefix("/oauth/token") {
				var sessionUUID: UUID

				if let sessionIDHeader = request.sessionID,
				   let existingSessionUUID = UUID(uuidString: sessionIDHeader) {
					sessionUUID = existingSessionUUID
				} else {
					sessionUUID = UUID()
				}

				if let tokenResponse = try? JSONDecoder().decode(OAuthTokenResponse.self, from: data),
				   tokenResponse.tokenType.lowercased() == "bearer",
				   await config.validate(token: tokenResponse.accessToken) {

					let expiresIn = tokenResponse.expiresIn ?? (24 * 60 * 60)

					await sessionManager.session(id: sessionUUID).work { s in
						await s.setAccessToken(tokenResponse.accessToken)
						await s.setAccessTokenExpiry(Date().addingTimeInterval(TimeInterval(expiresIn)))
						await s.setIDToken(tokenResponse.idToken)
					}

					if let oauthConfiguration {
						await sessionManager.fetchAndStoreUserInfo(for: sessionUUID, oauthConfiguration: oauthConfiguration)
					}

					responseHeaders.append(("Mcp-Session-Id", sessionUUID.uuidString))
					logger.info("Stored validated access token in session \(sessionUUID.uuidString)")
				}
			}

			// Copy response headers from upstream, excluding hop-by-hop headers
			let headersToExclude = [
				"transfer-encoding", "connection", "content-encoding",
				"access-control-allow-origin", "access-control-allow-methods",
				"access-control-allow-headers", "access-control-expose-headers",
				"access-control-max-age"
			]

			httpResponse.allHeaderFields.forEach { key, value in
				if let keyString = key as? String, let valueString = value as? String,
				   !headersToExclude.contains(keyString.lowercased()) {
					if keyString.lowercased() == "location" {
						if valueString.hasPrefix("/") {
							let baseURL = "\(config.issuer.scheme!)://\(config.issuer.host!)"
							let absoluteURL = baseURL + valueString
							responseHeaders.append((keyString, absoluteURL))
							logger.info("Converted relative Location header '\(valueString)' to absolute: '\(absoluteURL)'")
						} else {
							responseHeaders.append((keyString, valueString))
						}
					} else {
						responseHeaders.append((keyString, valueString))
					}
				}
			}

			responseHeaders.append(("Content-Length", "\(data.count)"))

			return RouteResponse(
				status: HTTPStatus(rawValue: httpResponse.statusCode),
				headers: responseHeaders,
				body: data
			)
		} catch {
			let err = JSONRPCMessage.errorResponse(
				id: nil,
				error: .init(code: -32603, message: "Failed to proxy request to OAuth server: \(error.localizedDescription)")
			)
			return .json(err, status: .internalServerError)
		}
	}

	// MARK: - Helpers

	/// Extract the base URL (scheme + host) from the request headers.
	private func getBaseURL(from request: HTTPRouteRequest<Data?>) -> String {
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
