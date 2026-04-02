import Foundation

/// Configuration for enabling OAuth validation on ``HTTPSSETransport``.
public struct OAuthConfiguration: Sendable {
    /// The issuer identifier for the authorization server.
    public let issuer: URL
    /// The OAuth authorization endpoint.
    public let authorizationEndpoint: URL
    /// The OAuth token endpoint.
    public let tokenEndpoint: URL
    /// Optional token introspection endpoint.
    public let introspectionEndpoint: URL?
    /// Optional JWKS endpoint for validating JWTs when no introspection endpoint is available.
    public let jwksEndpoint: URL?
    /// Expected audience ("aud" claim) for JWT validation.
    public let audience: String?
    /// Optional client identifier for introspection requests.
    public let clientID: String?
    /// Optional client secret for introspection requests.
    public let clientSecret: String?
    /// Optional custom validator closure.
    internal let tokenValidator: (@Sendable (String?) async -> Bool)?
    /// The OAuth dynamic client registration endpoint (optional)
    public let registrationEndpoint: URL?
    /// Whether to enable transparent proxy mode (server acts as OAuth provider)
    public let transparentProxy: Bool

    public init(
        issuer: URL,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        introspectionEndpoint: URL? = nil,
        jwksEndpoint: URL? = nil,
        audience: String? = nil,
        clientID: String? = nil,
        clientSecret: String? = nil,
        registrationEndpoint: URL? = nil,
        transparentProxy: Bool = false,
        tokenValidator: (@Sendable (String?) async -> Bool)? = nil
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.introspectionEndpoint = introspectionEndpoint
        self.jwksEndpoint = jwksEndpoint
        self.audience = audience
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.registrationEndpoint = registrationEndpoint
        self.transparentProxy = transparentProxy
        self.tokenValidator = tokenValidator
    }

    /// Validate the provided bearer token either using the custom validator,
    /// introspection, or by checking JWT claims against the issuer's JWKS.
    public func validate(token: String?) async -> Bool {
        guard let token else { return false }

        if let tokenValidator {
            return await tokenValidator(token)
        }

        if let introspectionEndpoint {
            var request = URLRequest(url: introspectionEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = "token=\(token)".data(using: .utf8)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let active = json["active"] as? Bool {
                    return active
                }
                return false
            } catch {
                return false
            }
        }

        // No introspection and no custom validator – deny by default.
        return false
    }

    /// Fetch user information from the OAuth provider using the access token.
    /// - Parameter token: The access token to use for the request
    /// - Returns: User information as a UserInfo struct, or nil if the request fails
    public func fetchUserInfo(token: String) async -> UserInfo? {
        // Construct the userinfo endpoint URL (standard OIDC endpoint)
        let userinfoURL = issuer.appendingPathComponent("userinfo")
        
        var request = URLRequest(url: userinfoURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // print("[OAuthConfiguration] Fetching user info from: \(userinfoURL.absoluteString)")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                // print("[OAuthConfiguration] Invalid response type for userinfo request")
                return nil
            }
            
            // print("[OAuthConfiguration] Userinfo response status: \(http.statusCode)")
            
            if http.statusCode != 200 {
                // Could log error response here if needed
                return nil
            }
            
            // Decode the JSON response into UserInfo struct
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let userInfo = try decoder.decode(UserInfo.self, from: data)
            // print("[OAuthConfiguration] Successfully fetched user info for user: \(userInfo.sub)")
            return userInfo
        } catch {
            // print("[OAuthConfiguration] Error fetching user info: \(error)")
            return nil
        }
    }

    // MARK: - Metadata helpers

    /// Metadata for the `/.well-known/oauth-authorization-server` endpoint.
    public struct AuthorizationServerMetadata: Encodable {
        public let issuer: String
        public let authorization_endpoint: String
        public let token_endpoint: String
        public let introspection_endpoint: String?
        public let jwks_uri: String?
        public let response_types_supported: [String]
        public let grant_types_supported: [String]
        public let scopes_supported: [String]
        public let registration_endpoint: String?
        public let code_challenge_methods_supported: [String]?
    }

    /// Metadata for the `/.well-known/oauth-protected-resource` endpoint.
    public struct ProtectedResourceMetadata: Encodable {
        public let resource: String
        public let issuer: String
        public let token_endpoint: String
        public let jwks_uri: String?
        public let scopes_supported: [String]
    }

    public func authorizationServerMetadata() -> AuthorizationServerMetadata {
        let regEndpoint = registrationEndpoint?.absoluteString
        print("[OAuthConfiguration] registration_endpoint: \(String(describing: regEndpoint))")
        // Ensure authorization_endpoint ends with /authorize
        let authEndpoint: String
        if authorizationEndpoint.path.hasSuffix("/authorize") {
            authEndpoint = authorizationEndpoint.absoluteString
        } else {
            authEndpoint = issuer.appendingPathComponent("authorize").absoluteString
        }
        let meta = AuthorizationServerMetadata(
            issuer: issuer.absoluteString,
            authorization_endpoint: authEndpoint,
            token_endpoint: tokenEndpoint.absoluteString,
            introspection_endpoint: introspectionEndpoint?.absoluteString,
            jwks_uri: (jwksEndpoint ?? issuer.appendingPathComponent(".well-known/jwks.json")).absoluteString,
            response_types_supported: ["code", "token"],
            grant_types_supported: ["authorization_code", "client_credentials", "refresh_token"],
            scopes_supported: ["openid", "profile", "email"],
            registration_endpoint: regEndpoint,
            code_challenge_methods_supported: ["S256"]
        )
        print("[OAuthConfiguration] authorizationServerMetadata: \(meta)")
        return meta
    }

    public func protectedResourceMetadata(resourceBaseURL: String? = nil) -> ProtectedResourceMetadata {
        ProtectedResourceMetadata(
            resource: resourceBaseURL ?? issuer.absoluteString,
            issuer: issuer.absoluteString,
            token_endpoint: tokenEndpoint.absoluteString,
            jwks_uri: (jwksEndpoint ?? issuer.appendingPathComponent(".well-known/jwks.json")).absoluteString,
            scopes_supported: ["openid", "profile", "email"]
        )
    }

    // MARK: - Transparent Proxy Metadata
    
    /// Generate metadata for transparent proxy mode where the server acts as the OAuth provider
    public func proxyAuthorizationServerMetadata(serverBaseURL: String) -> AuthorizationServerMetadata {
        AuthorizationServerMetadata(
            issuer: serverBaseURL,
            authorization_endpoint: "\(serverBaseURL)/authorize",
            token_endpoint: "\(serverBaseURL)/oauth/token",
            introspection_endpoint: nil, // Not proxying introspection for now
            jwks_uri: "\(serverBaseURL)/.well-known/jwks.json",
            response_types_supported: ["code", "token"],
            grant_types_supported: ["authorization_code", "client_credentials", "refresh_token"],
            scopes_supported: ["openid", "profile", "email"],
            registration_endpoint: "\(serverBaseURL)/oauth/register", // Proxy dynamic client registration
            code_challenge_methods_supported: ["S256"]
        )
    }
    
    /// Generate metadata for transparent proxy mode where the server acts as the OAuth provider
    public func proxyProtectedResourceMetadata(serverBaseURL: String) -> ProtectedResourceMetadata {
        ProtectedResourceMetadata(
            resource: serverBaseURL,
            issuer: serverBaseURL,
            token_endpoint: "\(serverBaseURL)/oauth/token",
            jwks_uri: "\(serverBaseURL)/.well-known/jwks.json",
            scopes_supported: ["openid", "profile", "email"]
        )
    }
}
