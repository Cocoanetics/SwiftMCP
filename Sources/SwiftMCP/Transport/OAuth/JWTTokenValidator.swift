//
//  JWTTokenValidator.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 02.07.25.
//

import Foundation

// MARK: - Convenience Token Validator

/// A lightweight JWT token validator for use with OAuthConfiguration
public struct JWTTokenValidator: Sendable {
    private let options: JWTValidationOptions
    private let jwksCache: JWKSCache
    
    /// Initialize a JWT token validator
    /// - Parameters:
    ///   - expectedIssuer: The expected issuer (e.g., "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
    ///   - expectedAudience: The expected audience (e.g., "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/")
    ///   - expectedAuthorizedParty: The expected authorized party / client ID (e.g., "n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi")
    ///   - allowedClockSkew: Clock skew tolerance in seconds (default: 60)
    ///   - cacheValidityDuration: How long to cache JWKS (default: 1 hour)
    public init(expectedIssuer: String? = nil, expectedAudience: String? = nil, expectedAuthorizedParty: String? = nil, allowedClockSkew: TimeInterval = 60, cacheValidityDuration: TimeInterval = 3600) {
        self.options = JWTValidationOptions(
            expectedIssuer: expectedIssuer,
            expectedAudience: expectedAudience,
            expectedAuthorizedParty: expectedAuthorizedParty,
            allowedClockSkew: allowedClockSkew
        )
        self.jwksCache = JWKSCache(cacheValidityDuration: cacheValidityDuration)
    }
    
    /// Validate a JWT token string (for use with OAuthConfiguration)
    /// - Parameter token: The JWT token to validate
    /// - Returns: true if the token is valid, false otherwise
    public func validate(_ token: String?) async -> Bool {
        guard let token = token else { return false }
        do {
            let jwt = try JSONWebToken(token: token)
            
            // First validate claims
            try jwt.validateClaims(options: options)
            
            // Then verify signature if we have an expected issuer
            if let expectedIssuer = options.expectedIssuer,
               let issuerURL = URL(string: expectedIssuer) {
                let jwks = try await jwksCache.getJWKS(for: issuerURL)
                return try jwt.verifySignature(using: jwks)
            }
            
            // If no issuer expected, just claims validation is sufficient
            return true
        } catch {
            return false
        }
    }
}
