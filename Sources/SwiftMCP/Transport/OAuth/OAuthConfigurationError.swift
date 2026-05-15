import Foundation

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

    internal enum CodingKeys: String, CodingKey {
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
        let issuerURL = try parseRequiredURL(issuer, label: "issuer")
        let authURL = try parseRequiredURL(authorizationEndpoint, label: "authorization_endpoint")
        let tokenURL = try parseRequiredURL(tokenEndpoint, label: "token_endpoint")

        let introspectionURL = try parseOptionalURL(introspectionEndpoint, label: "introspection_endpoint")
        let jwksURL = try parseOptionalURL(jwksEndpoint, label: "jwks_uri")
        let registrationURL = try parseOptionalURL(registrationEndpoint, label: "registration_endpoint")

        // Use JWT validation if no introspection endpoint is provided
        let tokenValidator: (@Sendable (String?) async -> Bool)? = if introspectionURL == nil {
            JWTTokenValidator(
                expectedIssuer: issuer,
                expectedAudience: audience,
                cacheValidityDuration: 3600 // 1 hour cache
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

    /// Parse a required URL string, throwing on failure.
    private func parseRequiredURL(_ value: String, label: String) throws -> URL {
        guard let url = URL(string: value) else {
            throw OAuthConfigurationError.invalidURL("\(label): \(value)")
        }
        return url
    }

    /// Parse an optional URL string, throwing only if a non-nil value is invalid.
    private func parseOptionalURL(_ value: String?, label: String) throws -> URL? {
        guard let value else { return nil }
        guard let url = URL(string: value) else {
            throw OAuthConfigurationError.invalidURL("\(label): \(value)")
        }
        return url
    }

    /// Load configuration from a JSON file
    public static func load(from filePath: String) throws -> JSONOAuthConfiguration {
        let url = URL(fileURLWithPath: filePath)
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(JSONOAuthConfiguration.self, from: data)
    }
}
