//
//  OAuthConfiguration+Auth0.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 02.07.25.
//

import Foundation

// MARK: - OAuthConfiguration Extensions

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
            expectedAudience: expectedAudience,
            cacheValidityDuration: 3600 // 1 hour cache
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
