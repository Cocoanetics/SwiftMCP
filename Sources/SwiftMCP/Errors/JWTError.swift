import Foundation

/// Errors that can occur during JWT operations
public enum JWTError: Error, Sendable {
    case invalidFormat
    case invalidBase64
    case invalidJSON
    case unsupportedAlgorithm
    case signatureVerificationFailed
    case jwksFetchFailed
    case keyNotFound
    case expired
    case notYetValid
    case invalidIssuer(expected: String, actual: String?)
    case invalidAudience(expected: String, actual: [String])
    case invalidAuthorizedParty(expected: String, actual: String?)
    case jweNotSupported
} 