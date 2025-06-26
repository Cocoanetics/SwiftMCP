import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration structure that can be loaded from JSON files
public struct JSONOAuthConfiguration: Codable, Sendable {
    /// The issuer identifier for the authorization server.
    public let issuer: String
    /// The OAuth authorization endpoint.
    public let authorizationEndpoint: String
    /// The OAuth token endpoint.
    public let tokenEndpoint: String
    /// Optional token introspection endpoint.
    public let introspectionEndpoint: String?
    /// Optional JWKS endpoint for validating JWTs when no introspection endpoint is available.
    public let jwksEndpoint: String?
    /// Expected audience ("aud" claim) for JWT validation.
    public let audience: String?
    /// Optional client identifier for introspection requests.
    public let clientID: String?
    /// Optional client secret for introspection requests.
    public let clientSecret: String?
    /// The OAuth dynamic client registration endpoint (optional)
    public let registrationEndpoint: String?
    /// Whether to enable transparent proxy mode (server acts as OAuth provider)
    public let transparentProxy: Bool?
    
    private enum CodingKeys: String, CodingKey {
        case issuer
        case authorizationEndpoint = "authorization_endpoint"
        case tokenEndpoint = "token_endpoint"
        case introspectionEndpoint = "introspection_endpoint"
        case jwksEndpoint = "jwks_uri"
        case audience
        case clientID = "client_id"
        case clientSecret = "client_secret"
        case registrationEndpoint = "registration_endpoint"
        case transparentProxy = "transparent_proxy"
    }
    
    /// Convert to OAuthConfiguration
    public func toOAuthConfiguration() throws -> OAuthConfiguration {
        guard let issuerURL = URL(string: issuer) else {
            throw OAuthConfigurationError.invalidURL("issuer: \(issuer)")
        }
        guard let authURL = URL(string: authorizationEndpoint) else {
            throw OAuthConfigurationError.invalidURL("authorization_endpoint: \(authorizationEndpoint)")
        }
        guard let tokenURL = URL(string: tokenEndpoint) else {
            throw OAuthConfigurationError.invalidURL("token_endpoint: \(tokenEndpoint)")
        }
        
        var introspectionURL: URL?
        if let introspectionEndpoint = introspectionEndpoint {
            guard let url = URL(string: introspectionEndpoint) else {
                throw OAuthConfigurationError.invalidURL("introspection_endpoint: \(introspectionEndpoint)")
            }
            introspectionURL = url
        }
        
        var jwksURL: URL?
        if let jwksEndpoint = jwksEndpoint {
            guard let url = URL(string: jwksEndpoint) else {
                throw OAuthConfigurationError.invalidURL("jwks_uri: \(jwksEndpoint)")
            }
            jwksURL = url
        }
        
        var registrationURL: URL?
        if let registrationEndpoint = registrationEndpoint {
            guard let url = URL(string: registrationEndpoint) else {
                throw OAuthConfigurationError.invalidURL("registration_endpoint: \(registrationEndpoint)")
            }
            registrationURL = url
        }
        
        // Use JWT validation if no introspection endpoint is provided
        let tokenValidator: (@Sendable (String?) async -> Bool)? = if introspectionURL == nil {
            JWTTokenValidator(
                expectedIssuer: issuer,
                expectedAudience: audience,
                expectedAuthorizedParty: clientID
            ).validate
        } else {
            nil
        }
        
        return OAuthConfiguration(
            issuer: issuerURL,
            authorizationEndpoint: authURL,
            tokenEndpoint: tokenURL,
            introspectionEndpoint: introspectionURL,
            jwksEndpoint: jwksURL,
            audience: audience,
            clientID: clientID,
            clientSecret: clientSecret,
            registrationEndpoint: registrationURL,
            transparentProxy: transparentProxy ?? false,
            tokenValidator: tokenValidator
        )
    }
    
    /// Load configuration from a JSON file
    public static func load(from filePath: String) throws -> JSONOAuthConfiguration {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(JSONOAuthConfiguration.self, from: data)
    }
}

public enum OAuthConfigurationError: Error, LocalizedError {
    case invalidURL(String)
    case fileNotFound(String)
    case invalidJSON(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let details):
            return "Invalid URL in OAuth configuration: \(details)"
        case .fileNotFound(let path):
            return "OAuth configuration file not found: \(path)"
        case .invalidJSON(let details):
            return "Invalid JSON in OAuth configuration: \(details)"
        }
    }
}

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
    private let tokenValidator: (@Sendable (String?) async -> Bool)?
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

private struct OIDCWellKnownConfiguration: Decodable, Sendable {
    let issuer: URL
    let authorization_endpoint: URL
    let token_endpoint: URL
    let introspection_endpoint: URL?
    let jwks_uri: URL
    let registration_endpoint: URL?
}

public extension OAuthConfiguration {
    init?(issuer: URL,
         audience: String? = nil,
         clientID: String? = nil,
         clientSecret: String? = nil,
         transparentProxy: Bool = false) async {
        let configURL = issuer.appendingPathComponent(".well-known/openid-configuration")

        do {
            let (data, response) = try await URLSession.shared.data(from: configURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let config = try JSONDecoder().decode(OIDCWellKnownConfiguration.self, from: data)

            self.init(
                issuer: config.issuer,
                authorizationEndpoint: config.authorization_endpoint,
                tokenEndpoint: config.token_endpoint,
                introspectionEndpoint: config.introspection_endpoint,
                jwksEndpoint: config.jwks_uri,
                audience: audience,
                clientID: clientID,
                clientSecret: clientSecret,
                registrationEndpoint: config.registration_endpoint,
                transparentProxy: transparentProxy
            )
        } catch {
            return nil
        }
    }
}

fileprivate struct DefaultJWSJWTPayload: Codable {
    let iss: String?
    let aud: [String]?
    let exp: Date?
    let nbf: Date?

    private enum CodingKeys: String, CodingKey {
        case iss, aud, exp, nbf
    }
    
    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        return try encoder.encode(self)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.iss = try container.decodeIfPresent(String.self, forKey: .iss)
        
        // Handle both single string and array for audience
        if let audString = try? container.decodeIfPresent(String.self, forKey: .aud) {
            self.aud = [audString]
        } else {
            self.aud = try container.decodeIfPresent([String].self, forKey: .aud)
        }
        
        self.exp = try container.decodeIfPresent(Date.self, forKey: .exp)
        self.nbf = try container.decodeIfPresent(Date.self, forKey: .nbf)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(iss, forKey: .iss)
        try container.encodeIfPresent(aud, forKey: .aud)
        try container.encodeIfPresent(exp, forKey: .exp)
        try container.encodeIfPresent(nbf, forKey: .nbf)
    }
}
