import Foundation

/// A JWT-based token validator that can be used with OAuthConfiguration
public struct JWTTokenValidator: Sendable {
    private let decoder: JWTDecoder
    private let expectedIssuer: String?
    private let expectedAudience: String?
    private let expectedAuthorizedParty: String?
    private let allowedClockSkew: TimeInterval
    
    /// Initialize a JWT token validator
    /// - Parameters:
    ///   - expectedIssuer: The expected issuer (e.g., "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
    ///   - expectedAudience: The expected audience (e.g., "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/")
    ///   - expectedAuthorizedParty: The expected authorized party / client ID (e.g., "n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi")
    ///   - allowedClockSkew: Clock skew tolerance in seconds (default: 60)
    public init(expectedIssuer: String? = nil, expectedAudience: String? = nil, expectedAuthorizedParty: String? = nil, allowedClockSkew: TimeInterval = 60) {
        self.decoder = JWTDecoder()
        self.expectedIssuer = expectedIssuer
        self.expectedAudience = expectedAudience
        self.expectedAuthorizedParty = expectedAuthorizedParty
        self.allowedClockSkew = allowedClockSkew
    }
    
    /// Validate a JWT token string
    /// - Parameter token: The JWT token to validate
    /// - Returns: true if the token is valid, false otherwise
    public func validate(_ token: String?) async -> Bool {
        guard let token = token else { return false }
        do {
            let options = JWTDecoder.ValidationOptions(
                expectedIssuer: expectedIssuer,
                expectedAudience: expectedAudience,
                expectedAuthorizedParty: expectedAuthorizedParty,
                allowedClockSkew: allowedClockSkew
            )
            _ = try decoder.decodeAndValidate(token, options: options)
            return true
        } catch {
            return false
        }
    }
    
    /// Decode and validate a JWT token, returning the decoded token for inspection
    /// - Parameter token: The JWT token to decode and validate
    /// - Returns: The decoded JWT token
    /// - Throws: JWTError if validation fails
    public func decodeAndValidate(_ token: String) throws -> JWTDecoder.DecodedJWT {
        let options = JWTDecoder.ValidationOptions(
            expectedIssuer: expectedIssuer,
            expectedAudience: expectedAudience,
            expectedAuthorizedParty: expectedAuthorizedParty,
            allowedClockSkew: allowedClockSkew
        )
        return try decoder.decodeAndValidate(token, options: options)
    }
    
    /// Extract user information from a valid JWT token
    /// - Parameter token: The JWT token to extract information from
    /// - Returns: A dictionary containing user information, or nil if token is invalid
    public func extractUserInfo(_ token: String) -> [String: Any]? {
        do {
            let jwt = try decodeAndValidate(token)
            var userInfo: [String: Any] = [:]
            
            if let sub = jwt.payload.sub {
                userInfo["sub"] = sub
            }
            if let iss = jwt.payload.iss {
                userInfo["iss"] = iss
            }
            if let scope = jwt.payload.scope {
                userInfo["scope"] = scope
            }
            if let azp = jwt.payload.azp {
                userInfo["azp"] = azp
            }
            if let exp = jwt.payload.exp {
                userInfo["exp"] = exp
            }
            if let iat = jwt.payload.iat {
                userInfo["iat"] = iat
            }
            if let aud = jwt.payload.aud {
                userInfo["aud"] = aud.values
            }
            
            return userInfo
        } catch {
            return nil
        }
    }
}

// MARK: - Convenience Extensions

extension OAuthConfiguration {
    /// Create an OAuth configuration with JWT token validation for Auth0
    /// - Parameters:
    ///   - auth0Domain: Your Auth0 domain (e.g., "dev-8ygj6eppnvjz8bm6.us.auth0.com")
    ///   - expectedAudience: The expected audience for your API
    ///   - clientId: Your Auth0 client ID
    ///   - clientSecret: Your Auth0 client secret
    /// - Returns: A configured OAuthConfiguration with JWT validation
    public static func auth0JWT(
        domain: String,
        expectedAudience: String,
        clientId: String,
        clientSecret: String
    ) -> OAuthConfiguration {
        let baseURL = "https://\(domain)"
        let expectedIssuer = "\(baseURL)/"
        
        let validator = JWTTokenValidator(
            expectedIssuer: expectedIssuer,
            expectedAudience: expectedAudience
        )
        
        return OAuthConfiguration(
            issuer: URL(string: baseURL)!,
            authorizationEndpoint: URL(string: "\(baseURL)/authorize")!,
            tokenEndpoint: URL(string: "\(baseURL)/oauth/token")!,
            clientID: clientId,
            clientSecret: clientSecret,
            tokenValidator: validator.validate
        )
    }
} 