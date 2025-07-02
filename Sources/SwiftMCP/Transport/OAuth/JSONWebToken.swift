import Foundation
import Crypto
import _CryptoExtras
import X509
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A comprehensive JSON Web Token (JWT) implementation with decoding, validation, and signature verification
public struct JSONWebToken: Sendable {
    
    /// The decoded JWT components
    public let header: JWTHeader
    public let payload: JWTPayload
    public let signature: String
    public let rawToken: String
    
    /// JWT Header structure
    public struct JWTHeader: Codable, Sendable {
        public let alg: String
        public let typ: String
        public let kid: String?
        
        public init(alg: String, typ: String, kid: String? = nil) {
            self.alg = alg
            self.typ = typ
            self.kid = kid
        }
    }
    
    /// JWT Payload structure
    public struct JWTPayload: Codable, Sendable {
        public let iss: String?
        public let sub: String?
        public let aud: AudienceValue?
        public let exp: Date?
        public let nbf: Date?
        public let iat: Date?
        public let scope: String?
        public let azp: String?
        
        public init(iss: String? = nil, sub: String? = nil, aud: AudienceValue? = nil, 
                   exp: Date? = nil, nbf: Date? = nil, iat: Date? = nil, 
                   scope: String? = nil, azp: String? = nil) {
            self.iss = iss
            self.sub = sub
            self.aud = aud
            self.exp = exp
            self.nbf = nbf
            self.iat = iat
            self.scope = scope
            self.azp = azp
        }
    }
    
    /// Audience can be either a string or an array of strings
    public enum AudienceValue: Codable, Equatable, Sendable {
        case single(String)
        case multiple([String])
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let single = try? container.decode(String.self) {
                self = .single(single)
            } else if let multiple = try? container.decode([String].self) {
                self = .multiple(multiple)
            } else {
                throw DecodingError.typeMismatch(AudienceValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected String or [String]"))
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .single(let value):
                try container.encode(value)
            case .multiple(let values):
                try container.encode(values)
            }
        }
        
        /// Check if the audience contains a specific value
        public func contains(_ value: String) -> Bool {
            switch self {
            case .single(let aud):
                return aud == value
            case .multiple(let auds):
                return auds.contains(value)
            }
        }
        
        /// Get all audience values as an array
        public var values: [String] {
            switch self {
            case .single(let value):
                return [value]
            case .multiple(let values):
                return values
            }
        }
    }
    
    // MARK: - Initialization
    
    /// Initialize a JWT from a token string
    /// - Parameter token: The JWT token string
    /// - Throws: JWTError if the token is malformed
    public init(token: String) throws {
        let segments = token.split(separator: ".")
        
        // Check for JWE format (5 segments: header.encrypted_key.iv.ciphertext.tag)
        if segments.count == 5 {
            throw JWTError.jweNotSupported
        }
        
        // Check for JWS format (3 segments: header.payload.signature)
        guard segments.count == 3 else {
            throw JWTError.invalidFormat
        }
        
        let headerData = try Data(base64URLEncoded: String(segments[0]))
        let payloadData = try Data(base64URLEncoded: String(segments[1]))
        let signature = String(segments[2])
        
        let header: JWTHeader
        let payload: JWTPayload
        
        do {
            header = try JSONDecoder().decode(JWTHeader.self, from: headerData)
        } catch {
            throw JWTError.invalidJSON
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            payload = try decoder.decode(JWTPayload.self, from: payloadData)
        } catch {
            throw JWTError.invalidJSON
        }
        
        self.header = header
        self.payload = payload
        self.signature = signature
        self.rawToken = token
    }
    
    // MARK: - Claims Validation
    
    /// Validate the JWT claims (exp, nbf, etc.) at a specific date
    /// - Parameters:
    ///   - date: The date to validate against (defaults to current date)
    ///   - options: Additional validation options
    /// - Throws: JWTError if validation fails
    public func validateClaims(at date: Date = Date(), options: JWTValidationOptions = JWTValidationOptions()) throws {
        // Check expiration
        if let exp = payload.exp {
            if date.timeIntervalSince(exp) > options.allowedClockSkew {
                throw JWTError.expired
            }
        }
        
        // Check not before
        if let nbf = payload.nbf {
            if nbf.timeIntervalSince(date) > options.allowedClockSkew {
                throw JWTError.notYetValid
            }
        }
        
        // Check issuer
        if let expectedIssuer = options.expectedIssuer {
            guard payload.iss == expectedIssuer else {
                throw JWTError.invalidIssuer(expected: expectedIssuer, actual: payload.iss)
            }
        }
        
        // Check audience
        if let expectedAudience = options.expectedAudience {
            guard let audience = payload.aud, audience.contains(expectedAudience) else {
                let actualAudiences = payload.aud?.values ?? []
                throw JWTError.invalidAudience(expected: expectedAudience, actual: actualAudiences)
            }
        }
        
        // Check authorized party
        if let expectedAzp = options.expectedAuthorizedParty {
            guard payload.azp == expectedAzp else {
                throw JWTError.invalidAuthorizedParty(expected: expectedAzp, actual: payload.azp)
            }
        }
    }
    
    // MARK: - Signature Verification
    
    /// Verify the JWT signature using a JSONWebKeySet
    /// - Parameter jwks: The JSON Web Key Set containing the public keys
    /// - Returns: True if the signature is valid
    /// - Throws: JWTError if verification fails
    public func verifySignature(using jwks: JSONWebKeySet) throws -> Bool {
        // Check algorithm
        guard header.alg == "RS256" else {
            throw JWTError.unsupportedAlgorithm
        }
        
        // Get the key ID
        guard let kid = header.kid else {
            throw JWTError.keyNotFound
        }
        
        // Get the public key from JWKS
        guard let publicKey = jwks.key(kid: kid) else {
            throw JWTError.keyNotFound
        }
        
        // Verify the signature
        // Split the token
        let segments = rawToken.split(separator: ".")
        guard segments.count == 3 else {
            throw JWTError.invalidFormat
        }
        
        // Prepare the signing input and signature data
        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        let signatureData = try Data(base64URLEncoded: String(segments[2]))
        
        // Verify the signature using Swift Crypto
        do {
            let signature = _RSA.Signing.RSASignature(rawRepresentation: signatureData)
            let isValid = publicKey.isValidSignature(signature, for: signingInput, padding: .insecurePKCS1v1_5)
            
            if !isValid {
                throw JWTError.signatureVerificationFailed
            }
            
            return true
        } catch {
            // If signature creation or verification fails, it's an invalid signature
            throw JWTError.signatureVerificationFailed
        }
    }
    
    // MARK: - Combined Verification
    
    /// Verify signature and validate claims in one step
    /// - Parameters:
    ///   - jwks: The JSON Web Key Set containing the public keys
    ///   - date: The date to validate against (defaults to current date)
    ///   - options: Additional validation options
    /// - Returns: True if both signature and claims are valid
    /// - Throws: JWTError if verification fails
    public func verify(using jwks: JSONWebKeySet, at date: Date = Date(), options: JWTValidationOptions = JWTValidationOptions()) throws -> Bool {
        // First validate claims
        try validateClaims(at: date, options: options)
        
        // Then verify signature
        return try verifySignature(using: jwks)
    }
    
    /// Fetch JWKS from the issuer and verify the token
    /// - Parameters:
    ///   - issuer: The JWT issuer URL (used to construct JWKS URL)
    ///   - date: The date to validate against (defaults to current date)
    ///   - options: Additional validation options
    ///   - jwksCache: Optional JWKS cache to use (creates new one if not provided)
    /// - Returns: True if the token is valid
    /// - Throws: JWTError if verification fails
    public func verify(using issuer: URL, at date: Date = Date(), options: JWTValidationOptions = JWTValidationOptions(), jwksCache: JWKSCache? = nil) async throws -> Bool {
        let cache = jwksCache ?? JWKSCache()
        let jwks = try await cache.getJWKS(for: issuer)
        return try verify(using: jwks, at: date, options: options)
    }
}
