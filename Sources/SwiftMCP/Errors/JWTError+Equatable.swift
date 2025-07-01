import Foundation

extension JWTError: Equatable {
    public static func == (lhs: JWTError, rhs: JWTError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidFormat, .invalidFormat),
             (.invalidBase64, .invalidBase64),
             (.invalidJSON, .invalidJSON),
             (.unsupportedAlgorithm, .unsupportedAlgorithm),
             (.signatureVerificationFailed, .signatureVerificationFailed),
             (.jwksFetchFailed, .jwksFetchFailed),
             (.keyNotFound, .keyNotFound),
             (.expired, .expired),
             (.notYetValid, .notYetValid),
             (.jweNotSupported, .jweNotSupported):
            return true
        case (.invalidIssuer(let lExpected, let lActual), .invalidIssuer(let rExpected, let rActual)):
            return lExpected == rExpected && lActual == rActual
        case (.invalidAudience(let lExpected, let lActual), .invalidAudience(let rExpected, let rActual)):
            return lExpected == rExpected && lActual == rActual
        case (.invalidAuthorizedParty(let lExpected, let lActual), .invalidAuthorizedParty(let rExpected, let rActual)):
            return lExpected == rExpected && lActual == rActual
        default:
            return false
        }
    }
} 