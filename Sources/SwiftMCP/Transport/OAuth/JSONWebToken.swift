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
    
    /// JWKS (JSON Web Key Set) for signature verification
    public struct JWKS: Codable, Sendable {
        public let keys: [JWK]
        
        public init(keys: [JWK]) {
            self.keys = keys
        }
    }
    
    /// JSON Web Key for signature verification
    public struct JWK: Codable, Sendable {
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
    
    /// Validation options for JWT tokens
    public struct ValidationOptions: Sendable {
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
    
    /// Errors that can occur during JWT operations
    public enum JWTError: Error, LocalizedError, Sendable, Equatable {
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
    public func validateClaims(at date: Date = Date(), options: ValidationOptions = ValidationOptions()) throws {
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
    
    /// Verify the JWT signature using a JWKS
    /// - Parameter jwks: The JSON Web Key Set containing the public keys
    /// - Returns: True if the signature is valid
    /// - Throws: JWTError if verification fails
    public func verifySignature(using jwks: JWKS) throws -> Bool {
        // Check algorithm
        guard header.alg == "RS256" else {
            throw JWTError.unsupportedAlgorithm
        }
        
        // Get the key ID
        guard let kid = header.kid else {
            throw JWTError.keyNotFound
        }
        
        // Find the key with matching kid
        guard let jwk = jwks.keys.first(where: { $0.kid == kid }) else {
            throw JWTError.keyNotFound
        }
        
        // Verify the signature
        return try Self.verifyRS256Signature(
            token: rawToken,
            publicKeyModulus: jwk.n,
            publicKeyExponent: jwk.e,
            x5c: jwk.x5c
        )
    }
    
    // MARK: - Combined Verification
    
    /// Verify signature and validate claims in one step
    /// - Parameters:
    ///   - jwks: The JSON Web Key Set containing the public keys
    ///   - date: The date to validate against (defaults to current date)
    ///   - options: Additional validation options
    /// - Returns: True if both signature and claims are valid
    /// - Throws: JWTError if verification fails
    public func verify(using jwks: JWKS, at date: Date = Date(), options: ValidationOptions = ValidationOptions()) throws -> Bool {
        // First validate claims
        try validateClaims(at: date, options: options)
        
        // Then verify signature
        return try verifySignature(using: jwks)
    }
    
    /// Fetch JWKS from the issuer and verify the token
    /// - Parameters:
    ///   - issuer: The JWT issuer (used to construct JWKS URL)
    ///   - date: The date to validate against (defaults to current date)
    ///   - options: Additional validation options
    /// - Returns: True if the token is valid
    /// - Throws: JWTError if verification fails
    public func verify(using issuer: String, at date: Date = Date(), options: ValidationOptions = ValidationOptions()) async throws -> Bool {
        let jwks = try await Self.fetchJWKS(from: issuer)
        return try verify(using: jwks, at: date, options: options)
    }
    
    // MARK: - Convenience Methods
    
    /// Extract user information from the JWT payload
    /// - Returns: A dictionary containing user information
    public func extractUserInfo() -> [String: Any] {
        var userInfo: [String: Any] = [:]
        
        if let sub = payload.sub {
            userInfo["sub"] = sub
        }
        if let iss = payload.iss {
            userInfo["iss"] = iss
        }
        if let scope = payload.scope {
            userInfo["scope"] = scope
        }
        if let azp = payload.azp {
            userInfo["azp"] = azp
        }
        if let exp = payload.exp {
            userInfo["exp"] = exp
        }
        if let iat = payload.iat {
            userInfo["iat"] = iat
        }
        if let aud = payload.aud {
            userInfo["aud"] = aud.values
        }
        
        return userInfo
    }
    
    // MARK: - Static helpers
    
    /// Fetch JWKS from the issuer
    /// - Parameter issuer: The JWT issuer
    /// - Returns: JWKS response
    /// - Throws: JWTError if fetch fails
    public static func fetchJWKS(from issuer: String) async throws -> JWKS {
        let jwksURL = "\(issuer).well-known/jwks.json"
        
        guard let url = URL(string: jwksURL) else {
            throw JWTError.jwksFetchFailed
        }
        
        #if canImport(FoundationNetworking)
        // For Linux/cross-platform environments, use FoundationNetworking
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: JWTError.jwksFetchFailed)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data else {
                    continuation.resume(throwing: JWTError.jwksFetchFailed)
                    return
                }
                
                do {
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .secondsSince1970
                    let jwks = try decoder.decode(JWKS.self, from: data)
                    continuation.resume(returning: jwks)
                } catch {
                    continuation.resume(throwing: JWTError.jwksFetchFailed)
                }
            }
            task.resume()
        }
        #else
        // For Darwin/macOS/iOS environments, use standard URLSession
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw JWTError.jwksFetchFailed
        }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try decoder.decode(JWKS.self, from: data)
        #endif
    }
    
    // MARK: - Private helpers
    
    /// Verify RS256 signature using Swift Crypto framework
    /// - Parameters:
    ///   - token: The JWT token
    ///   - publicKeyModulus: RSA modulus (base64url encoded)
    ///   - publicKeyExponent: RSA exponent (base64url encoded)
    ///   - x5c: X.509 certificate chain (optional)
    /// - Returns: True if signature is valid
    /// - Throws: JWTError if verification fails
    private static func verifyRS256Signature(
        token: String,
        publicKeyModulus: String,
        publicKeyExponent: String,
        x5c: [String]? = nil
    ) throws -> Bool {
        // Split the token
        let segments = token.split(separator: ".")
        guard segments.count == 3 else {
            throw JWTError.invalidFormat
        }
        
        // Prepare the signing input and signature data
        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        let signatureData = try Data(base64URLEncoded: String(segments[2]))
        
        // Create RSA public key using Swift Crypto
        let publicKey = try createRSAPublicKeyFromJWK(
            modulus: publicKeyModulus,
            exponent: publicKeyExponent,
            x5c: x5c
        )
        
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
    
    /// Create RSA public key from JWK parameters using Swift Crypto
    /// - Parameters:
    ///   - modulus: RSA modulus (base64url encoded)
    ///   - exponent: RSA exponent (base64url encoded)
    ///   - x5c: X.509 certificate chain (optional)
    /// - Returns: RSA.Signing.PublicKey from Swift Crypto
    /// - Throws: JWTError if key creation fails
    private static func createRSAPublicKeyFromJWK(
        modulus: String,
        exponent: String,
        x5c: [String]? = nil
    ) throws -> _RSA.Signing.PublicKey {
        // For now, focus on manual key construction from modulus/exponent
        // TODO: Add X.509 certificate parsing when swift-certificates API is stable
        
        // Create key from modulus / exponent in the JWKS
        let modulusData = try Data(base64URLEncoded: modulus)
        let exponentData = try Data(base64URLEncoded: exponent)
        
        return try _RSA.Signing.PublicKey(n: modulusData, e: exponentData)
    }


}

// MARK: - Convenience Token Validator

/// A lightweight JWT token validator for use with OAuthConfiguration
public struct JWTTokenValidator: Sendable {
    private let options: JSONWebToken.ValidationOptions
    
    /// Initialize a JWT token validator
    /// - Parameters:
    ///   - expectedIssuer: The expected issuer (e.g., "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
    ///   - expectedAudience: The expected audience (e.g., "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/")
    ///   - expectedAuthorizedParty: The expected authorized party / client ID (e.g., "n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi")
    ///   - allowedClockSkew: Clock skew tolerance in seconds (default: 60)
    public init(expectedIssuer: String? = nil, expectedAudience: String? = nil, expectedAuthorizedParty: String? = nil, allowedClockSkew: TimeInterval = 60) {
        self.options = JSONWebToken.ValidationOptions(
            expectedIssuer: expectedIssuer,
            expectedAudience: expectedAudience,
            expectedAuthorizedParty: expectedAuthorizedParty,
            allowedClockSkew: allowedClockSkew
        )
    }
    
    /// Validate a JWT token string (for use with OAuthConfiguration)
    /// - Parameter token: The JWT token to validate
    /// - Returns: true if the token is valid, false otherwise
    public func validate(_ token: String?) async -> Bool {
        guard let token = token else { return false }
        do {
            let jwt = try JSONWebToken(token: token)
            try jwt.validateClaims(options: options)
            return true
        } catch {
            return false
        }
    }
}

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
            expectedAudience: expectedAudience
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

// MARK: - Extension to handle base64URL decoding for JWT

extension Data {
    /// SwiftCrypto expects raw big-endian bytes.  
    /// JWT uses base64url with no padding.  
    init(base64URLEncoded source: String) throws {
        var padded = source.replacingOccurrences(of: "-", with: "+")
                           .replacingOccurrences(of: "_", with: "/")
        padded += String(repeating: "=", count: (4 - padded.count % 4) % 4)
        guard let d = Data(base64Encoded: padded) else {
            throw JSONWebToken.JWTError.invalidBase64
        }
        self = d
    }
} 