//
//  JWTValidationOptions.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 02.07.25.
//

import Foundation

/// Validation options for JWT tokens
/// 
/// This structure defines the validation criteria that will be applied when
/// validating JWT tokens. It includes standard JWT claims validation such as
/// issuer, audience, and timing checks.
public struct JWTValidationOptions: Sendable {
    /// The expected issuer of the JWT token
    /// 
    /// This should match the `iss` claim in the JWT payload. If provided,
    /// the validation will fail if the token's issuer doesn't match this value.
    /// 
    /// Example: `"https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"`
    public let expectedIssuer: String?
    
    /// The expected audience of the JWT token
    /// 
    /// This should match the `aud` claim in the JWT payload. If provided,
    /// the validation will fail if the token's audience doesn't match this value.
    /// 
    /// Example: `"https://api.example.com"`
    public let expectedAudience: String?
    
    /// The expected authorized party (client ID) of the JWT token
    /// 
    /// This should match the `azp` claim in the JWT payload. If provided,
    /// the validation will fail if the token's authorized party doesn't match this value.
    /// 
    /// Example: `"n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi"`
    public let expectedAuthorizedParty: String?
    
    /// Clock skew tolerance in seconds for timing validations
    /// 
    /// This value is used to allow for small differences between the server's
    /// clock and the JWT issuer's clock when validating `exp` (expiration)
    /// and `nbf` (not before) claims.
    /// 
    /// Default: 60 seconds
    public let allowedClockSkew: TimeInterval
    
    /// Initialize JWT validation options
    /// - Parameters:
    ///   - expectedIssuer: The expected issuer (optional)
    ///   - expectedAudience: The expected audience (optional)
    ///   - expectedAuthorizedParty: The expected authorized party (optional)
    ///   - allowedClockSkew: Clock skew tolerance in seconds (default: 60)
    public init(expectedIssuer: String? = nil, expectedAudience: String? = nil, expectedAuthorizedParty: String? = nil, allowedClockSkew: TimeInterval = 60) {
        self.expectedIssuer = expectedIssuer
        self.expectedAudience = expectedAudience
        self.expectedAuthorizedParty = expectedAuthorizedParty
        self.allowedClockSkew = allowedClockSkew
    }
}
