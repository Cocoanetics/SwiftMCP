import Foundation
import Crypto
import _CryptoExtras
import X509

/// JSON Web Key for signature verification
public struct JSONWebKey: Codable, Sendable {
    public let kty: String
    public let kid: String
    public let use: String?
    public let alg: String?
    public let n: String  // RSA modulus
    public let e: String  // RSA exponent
    public let x5c: [String]?  // X.509 certificate chain
    
    public init(kty: String, kid: String, use: String? = nil, alg: String? = nil, 
               n: String, e: String, x5c: [String]? = nil) {
        self.kty = kty
        self.kid = kid
        self.use = use
        self.alg = alg
        self.n = n
        self.e = e
        self.x5c = x5c
    }
    
    /// Create RSA public key from JWK parameters
    /// - Returns: RSA public key from Swift Crypto
    /// - Throws: JWTError if key creation fails
    public func createRSAPublicKey() throws -> _RSA.Signing.PublicKey {
        // If X.509 certificate chain is available, use it
        if let x5c = x5c, let certB64 = x5c.first {
            guard let certDER = Data(base64Encoded: certB64) else {
                throw JWTError.signatureVerificationFailed
            }
            
            let certificate = try X509.Certificate(derEncoded: Array(certDER))
            let pemDocument = try certificate.publicKey.serializeAsPEM()
            return try _RSA.Signing.PublicKey(pemRepresentation: pemDocument.pemString)
        }
        
        // Otherwise, create key from modulus/exponent in the JWKS
        let modulusData = try Data(base64URLEncoded: n)
        let exponentData = try Data(base64URLEncoded: e)
        return try _RSA.Signing.PublicKey(n: modulusData, e: exponentData)
    }
} 