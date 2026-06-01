import SwiftCross

extension HTTPSSETransport {
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
			if let redirectResponse = buildAuthorizeRedirect(config: config, requestURI: request.uri) {
				return redirectResponse
			}
		}

		// Determine the target URL based on the request path
		let resolved = resolveProxyTarget(config: config, requestURI: request.uri)
		switch resolved {
		case .target(let targetURL):
			return try await proxyRequestToUpstream(
				request: request,
				config: config,
				targetURL: targetURL
			)
		case .redirect(let response):
			return response
		case .unknown:
			logger.error("Unknown OAuth proxy path: \(request.uri)")
			let err = JSONRPCMessage.errorResponse(id: nil, error: .init(code: -32601, message: "Unknown OAuth endpoint"))
			return .json(err, status: .notFound)
		}
	}

	/// Build the redirect response for `/authorize` requests, or nil if components cannot be formed.
	private func buildAuthorizeRedirect(config: OAuthConfiguration, requestURI: String) -> RouteResponse? {
		var components = URLComponents(url: config.authorizationEndpoint, resolvingAgainstBaseURL: false)!

		if let originalComponents = URLComponents(string: "http://dummy\(requestURI)") {
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

		guard let redirectURL = components.url else { return nil }
		logger.info("Redirecting /authorize request to Auth0: \(redirectURL.absoluteString)")
		return RouteResponse(status: .found, headers: [("Location", redirectURL.absoluteString)])
	}

	/// Resolution of a request URI to a proxy target or redirect.
	private enum ProxyTargetResolution {
		case target(URL)
		case redirect(RouteResponse)
		case unknown
	}

	/// Map a request URI to its upstream target URL or redirect response.
	private func resolveProxyTarget(config: OAuthConfiguration, requestURI: String) -> ProxyTargetResolution {
		switch requestURI {
		case let path where path.hasPrefix("/oauth/token"):
			return .target(config.tokenEndpoint)
		case let path where path.hasPrefix("/oauth/register"):
			return .target(config.registrationEndpoint ?? config.issuer.appendingPathComponent("oidc/register"))
		case let path where path.hasPrefix("/oauth/"):
			let pathComponent = String(requestURI.dropFirst(1))
			return .target(config.issuer.appendingPathComponent(pathComponent))
		case "/userinfo":
			return .target(config.issuer.appendingPathComponent("userinfo"))
		case "/.well-known/jwks.json":
			return .target(config.jwksEndpoint ?? config.issuer.appendingPathComponent(".well-known/jwks.json"))
		case "/.well-known/openid-configuration":
			return .target(config.issuer.appendingPathComponent(".well-known/openid-configuration"))
		case let path where path.hasPrefix("/u/"):
			let redirectURL = config.issuer.appendingPathComponent(String(requestURI.dropFirst(1))).absoluteString
			logger.info("Redirecting Auth0 UI path to Auth0: \(redirectURL)")
			return .redirect(RouteResponse(status: .found, headers: [("Location", redirectURL)]))
		default:
			return .unknown
		}
	}

	/// Build the upstream URLRequest from the original request and target URL.
	private func makeProxyRequest(
		from request: HTTPRouteRequest<Data?>,
		config: OAuthConfiguration,
		targetURL: URL
	) -> URLRequest {
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
		return proxyRequest
	}

	/// Forward the proxy request to upstream and convert the response back to a RouteResponse.
	private func proxyRequestToUpstream(
		request: HTTPRouteRequest<Data?>,
		config: OAuthConfiguration,
		targetURL: URL
	) async throws -> RouteResponse {
		let proxyRequest = makeProxyRequest(from: request, config: config, targetURL: targetURL)

		do {
			let sessionConfig = URLSessionConfiguration.default
			let delegate = NoRedirectDelegate()
			let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
			let (data, response) = try await session.data(for: proxyRequest)

			guard let httpResponse = response as? HTTPURLResponse else {
				let err = JSONRPCMessage.errorResponse(
					id: nil,
					error: .init(code: -32603, message: "Invalid response from auth server")
				)
				return .json(err, status: .internalServerError)
			}

			var responseHeaders: [(String, String)] = []

			// Handle token response: validate and store access token in session
			if request.uri.hasPrefix("/oauth/token") {
				if let sessionUUID = await storeAccessTokenIfValid(request: request, config: config, data: data) {
					responseHeaders.append(("Mcp-Session-Id", sessionUUID.uuidString))
					logger.info("Stored validated access token in session \(sessionUUID.uuidString)")
				}
			}

			responseHeaders.append(contentsOf: copyUpstreamHeaders(from: httpResponse, config: config))
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

	/// Decode the upstream token response, validate the token, and persist it in a session. Returns the session ID.
	private func storeAccessTokenIfValid(
		request: HTTPRouteRequest<Data?>,
		config: OAuthConfiguration,
		data: Data
	) async -> UUID? {
		let sessionUUID: UUID
		if let sessionIDHeader = request.sessionID,
		   let existingSessionUUID = UUID(uuidString: sessionIDHeader) {
			sessionUUID = existingSessionUUID
		} else {
			sessionUUID = UUID()
		}

		guard let tokenResponse = try? JSONDecoder().decode(OAuthTokenResponse.self, from: data),
			  tokenResponse.tokenType.lowercased() == "bearer",
			  await config.validate(token: tokenResponse.accessToken) else {
			return nil
		}

		let expiresIn = tokenResponse.expiresIn ?? (24 * 60 * 60)

		await sessionManager.session(id: sessionUUID).work { session in
			await session.setAccessToken(tokenResponse.accessToken)
			await session.setAccessTokenExpiry(Date().addingTimeInterval(TimeInterval(expiresIn)))
			await session.setIDToken(tokenResponse.idToken)
		}

		if let oauthConfiguration {
			await sessionManager.fetchAndStoreUserInfo(for: sessionUUID, oauthConfiguration: oauthConfiguration)
		}
		return sessionUUID
	}

	/// Copy upstream response headers, filtering hop-by-hop and converting relative Location values.
	private func copyUpstreamHeaders(
		from httpResponse: HTTPURLResponse,
		config: OAuthConfiguration
	) -> [(String, String)] {
		let headersToExclude = [
			"transfer-encoding", "connection", "content-encoding",
			"access-control-allow-origin", "access-control-allow-methods",
			"access-control-allow-headers", "access-control-expose-headers",
			"access-control-max-age"
		]

		var responseHeaders: [(String, String)] = []
		httpResponse.allHeaderFields.forEach { key, value in
			guard let keyString = key as? String, let valueString = value as? String,
				  !headersToExclude.contains(keyString.lowercased()) else {
				return
			}
			if keyString.lowercased() == "location", valueString.hasPrefix("/") {
				let baseURL = "\(config.issuer.scheme!)://\(config.issuer.host!)"
				let absoluteURL = baseURL + valueString
				responseHeaders.append((keyString, absoluteURL))
				logger.info("Converted relative Location header '\(valueString)' to absolute: '\(absoluteURL)'")
			} else {
				responseHeaders.append((keyString, valueString))
			}
		}
		return responseHeaders
	}
}
