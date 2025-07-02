//
//  JWTValidationOptions.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 02.07.25.
//

import Foundation

/// Validation options for JWT tokens
public struct JWTValidationOptions: Sendable {
    public let expectedIssuer: String?
    public let expectedAudience: String?
    public let expectedAuthorizedParty: String?
    public let allowedClockSkew: TimeInterval
    
    public init(expectedIssuer: String? = nil, expectedAudience: String? = nil, expectedAuthorizedParty: String? = nil, allowedClockSkew: TimeInterval = 60) {
        self.expectedIssuer = expectedIssuer
        self.expectedAudience = expectedAudience
        self.expectedAuthorizedParty = expectedAuthorizedParty
        self.allowedClockSkew = allowedClockSkew
    }
}
