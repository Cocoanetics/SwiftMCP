import Foundation

extension JWTError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidFormat:
            return "JWT does not have the correct format (header.payload.signature)"
        case .invalidBase64:
            return "Failed to decode base64 encoded JWT segment"
        case .invalidJSON:
            return "Failed to parse JSON in JWT segment"
        case .unsupportedAlgorithm:
            return "Algorithm not supported for signature verification"
        case .signatureVerificationFailed:
            return "JWT signature verification failed"
        case .jwksFetchFailed:
            return "Failed to fetch JWKS from issuer"
        case .keyNotFound:
            return "Key with specified kid not found in JWKS"
        case .expired:
            return "JWT token has expired"
        case .notYetValid:
            return "JWT token is not yet valid"
        case .invalidIssuer(let expected, let actual):
            return "JWT issuer validation failed. Expected: \(expected), Actual: \(actual ?? "nil")"
        case .invalidAudience(let expected, let actual):
            return "JWT audience validation failed. Expected: \(expected), Actual: \(actual)"
        case .invalidAuthorizedParty(let expected, let actual):
            return "JWT authorized party validation failed. Expected: \(expected), Actual: \(actual ?? "nil")"
        case .jweNotSupported:
            return "Encrypted (JWE) tokens are not supported. Use a signed JWT (JWS)"
        }
    }
} 