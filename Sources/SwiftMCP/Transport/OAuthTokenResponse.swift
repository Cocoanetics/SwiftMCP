import Foundation

/// OAuth token response from the token endpoint
/// Based on RFC 6749 OAuth 2.0 specification
public struct OAuthTokenResponse: Codable, Sendable {
    /// The access token issued by the authorization server
    public let accessToken: String
    
    /// The type of the token issued (e.g., "Bearer")
    public let tokenType: String
    
    /// The lifetime in seconds of the access token
    public let expiresIn: Int?
    
    /// The refresh token, which can be used to obtain new access tokens
    public let refreshToken: String?
    
    /// The scope of the access token
    public let scope: String?
    
    /// ID token (for OpenID Connect)
    public let idToken: String?
    
    public init(
        accessToken: String,
        tokenType: String,
        expiresIn: Int? = nil,
        refreshToken: String? = nil,
        scope: String? = nil,
        idToken: String? = nil
    ) {
        self.accessToken = accessToken
        self.tokenType = tokenType
        self.expiresIn = expiresIn
        self.refreshToken = refreshToken
        self.scope = scope
        self.idToken = idToken
    }
    
    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
        case scope
        case idToken = "id_token"
    }
} 