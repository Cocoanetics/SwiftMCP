import Foundation
import Crypto
import _CryptoExtras
import X509

/// JSON Web Key (JWK) for signature verification according to RFC 7517
public struct JSONWebKey: Codable, Sendable {
    /// The key type (e.g., "RSA", "EC", "oct")
    public let kty: String
    
    /// The key ID used to identify this key in a JWKS
    public let kid: String
    
    /// The intended use of the key (e.g., "sig" for signing, "enc" for encryption)
    public let use: String?
    
    /// The algorithm this key is intended to be used with (e.g., "RS256", "ES256")
    public let alg: String?
    
    /// The RSA modulus (base64url encoded) - required for RSA keys
    public let n: String?
    
    /// The RSA exponent (base64url encoded) - required for RSA keys
    public let e: String?
    
    /// The X.509 certificate chain (base64 encoded DER certificates)
    public let x5c: [String]?
    
    /// Initialize a JSON Web Key
    /// - Parameters:
    ///   - kty: The key type
    ///   - kid: The key ID
    ///   - use: Optional intended use
    ///   - alg: Optional algorithm
    ///   - n: Optional RSA modulus
    ///   - e: Optional RSA exponent
    ///   - x5c: Optional X.509 certificate chain
    public init(kty: String, kid: String, use: String? = nil, alg: String? = nil, 
               n: String? = nil, e: String? = nil, x5c: [String]? = nil) {
        self.kty = kty
        self.kid = kid
        self.use = use
        self.alg = alg
        self.n = n
        self.e = e
        self.x5c = x5c
    }
    
    /// Create RSA public key from JWK parameters
    /// 
    /// This method supports two ways of creating RSA public keys:
    /// 1. From X.509 certificate chain (x5c) - preferred when available
    /// 2. From raw RSA parameters (n and e) - fallback when no certificate is provided
    /// 
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
        guard let n = n, let e = e else {
            throw JWTError.signatureVerificationFailed
        }
        
        let modulusData = try Data(base64URLEncoded: n)
        let exponentData = try Data(base64URLEncoded: e)
        return try _RSA.Signing.PublicKey(n: modulusData, e: exponentData)
    }
} 