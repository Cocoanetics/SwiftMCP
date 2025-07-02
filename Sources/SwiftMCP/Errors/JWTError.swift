import Foundation

/// Errors that can occur during JWT operations
/// 
/// This enum defines all possible errors that can occur when working with
/// JSON Web Tokens, including parsing, validation, and signature verification errors.
public enum JWTError: Error, Sendable {
    /// The JWT format is invalid (not three dot-separated parts)
    case invalidFormat
    
    /// Failed to decode base64url encoded JWT segments
    case invalidBase64
    
    /// Failed to parse JSON in JWT header or payload
    case invalidJSON
    
    /// The JWT algorithm is not supported for signature verification
    case unsupportedAlgorithm
    
    /// JWT signature verification failed
    case signatureVerificationFailed
    
    /// Failed to fetch JWKS from the issuer
    case jwksFetchFailed
    
    /// The key with the specified kid was not found in the JWKS
    case keyNotFound
    
    /// The JWT has expired
    case expired
    
    /// The JWT is not yet valid (nbf claim)
    case notYetValid
    
    /// The JWT issuer validation failed
    /// - Parameters:
    ///   - expected: The expected issuer value
    ///   - actual: The actual issuer value from the JWT
    case invalidIssuer(expected: String, actual: String?)
    
    /// The JWT audience validation failed
    /// - Parameters:
    ///   - expected: The expected audience value
    ///   - actual: The actual audience values from the JWT
    case invalidAudience(expected: String, actual: [String])
    
    /// The JWT authorized party validation failed
    /// - Parameters:
    ///   - expected: The expected authorized party value
    ///   - actual: The actual authorized party value from the JWT
    case invalidAuthorizedParty(expected: String, actual: String?)
    
    /// Encrypted JWT (JWE) tokens are not supported
    case jweNotSupported
} 