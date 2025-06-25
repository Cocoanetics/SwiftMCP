import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
         clientSecret: String? = nil) async {
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
                registrationEndpoint: config.registration_endpoint
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
