import Foundation

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
} 