import Foundation

/// A lightweight JWT decoder for basic validation without signature verification
public struct JWTDecoder: Sendable {
    
    /// Represents a decoded JWT token
    public struct DecodedJWT {
        public let header: JWTHeader
        public let payload: JWTPayload
        public let signature: String
        
        /// The original raw token string
        public let rawToken: String
    }
    
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
        
        private enum CodingKeys: String, CodingKey {
            case iss, sub, aud, exp, nbf, iat, scope, azp
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.iss = try container.decodeIfPresent(String.self, forKey: .iss)
            self.sub = try container.decodeIfPresent(String.self, forKey: .sub)
            self.aud = try container.decodeIfPresent(AudienceValue.self, forKey: .aud)
            self.scope = try container.decodeIfPresent(String.self, forKey: .scope)
            self.azp = try container.decodeIfPresent(String.self, forKey: .azp)
            
            // Handle date fields as Unix timestamps
            if let expTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .exp) {
                self.exp = Date(timeIntervalSince1970: expTimestamp)
            } else {
                self.exp = nil
            }
            
            if let nbfTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .nbf) {
                self.nbf = Date(timeIntervalSince1970: nbfTimestamp)
            } else {
                self.nbf = nil
            }
            
            if let iatTimestamp = try container.decodeIfPresent(TimeInterval.self, forKey: .iat) {
                self.iat = Date(timeIntervalSince1970: iatTimestamp)
            } else {
                self.iat = nil
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encodeIfPresent(iss, forKey: .iss)
            try container.encodeIfPresent(sub, forKey: .sub)
            try container.encodeIfPresent(aud, forKey: .aud)
            try container.encodeIfPresent(scope, forKey: .scope)
            try container.encodeIfPresent(azp, forKey: .azp)
            
            if let exp = exp {
                try container.encode(exp.timeIntervalSince1970, forKey: .exp)
            }
            if let nbf = nbf {
                try container.encode(nbf.timeIntervalSince1970, forKey: .nbf)
            }
            if let iat = iat {
                try container.encode(iat.timeIntervalSince1970, forKey: .iat)
            }
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
    
    /// Errors that can occur during JWT decoding
    public enum JWTError: Error, LocalizedError, Equatable {
        case invalidFormat
        case invalidBase64
        case invalidJSON
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
    
    /// Validation options for JWT tokens
    public struct ValidationOptions {
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
    
    public init() {}
    
    /// Decode a JWT token string into its components
    /// - Parameter token: The JWT token string
    /// - Returns: A DecodedJWT containing header, payload, and signature
    /// - Throws: JWTError if the token is malformed
    public func decode(_ token: String) throws -> DecodedJWT {
        let segments = token.split(separator: ".")
        
        // Check for JWE format (5 segments: header.encrypted_key.iv.ciphertext.tag)
        if segments.count == 5 {
            throw JWTError.jweNotSupported
        }
        
        // Check for JWS format (3 segments: header.payload.signature)
        guard segments.count == 3 else {
            throw JWTError.invalidFormat
        }
        
        let headerData = try base64URLDecode(String(segments[0]))
        let payloadData = try base64URLDecode(String(segments[1]))
        let signature = String(segments[2])
        
        let header: JWTHeader
        let payload: JWTPayload
        
        do {
            header = try JSONDecoder().decode(JWTHeader.self, from: headerData)
        } catch {
            throw JWTError.invalidJSON
        }
        
        do {
            payload = try JSONDecoder().decode(JWTPayload.self, from: payloadData)
        } catch {
            throw JWTError.invalidJSON
        }
        
        return DecodedJWT(header: header, payload: payload, signature: signature, rawToken: token)
    }
    
    /// Validate a decoded JWT token against the provided options
    /// - Parameters:
    ///   - jwt: The decoded JWT token
    ///   - options: Validation options
    /// - Throws: JWTError if validation fails
    public func validate(_ jwt: DecodedJWT, options: ValidationOptions) throws {
        let now = Date()
        
        // Check expiration
        if let exp = jwt.payload.exp {
            if now.timeIntervalSince(exp) > options.allowedClockSkew {
                throw JWTError.expired
            }
        }
        
        // Check not before
        if let nbf = jwt.payload.nbf {
            if nbf.timeIntervalSince(now) > options.allowedClockSkew {
                throw JWTError.notYetValid
            }
        }
        
        // Check issuer
        if let expectedIssuer = options.expectedIssuer {
            guard jwt.payload.iss == expectedIssuer else {
                throw JWTError.invalidIssuer(expected: expectedIssuer, actual: jwt.payload.iss)
            }
        }
        
        // Check audience
        if let expectedAudience = options.expectedAudience {
            guard let audience = jwt.payload.aud, audience.contains(expectedAudience) else {
                let actualAudiences = jwt.payload.aud?.values ?? []
                throw JWTError.invalidAudience(expected: expectedAudience, actual: actualAudiences)
            }
        }
        
        // Check authorized party
        if let expectedAzp = options.expectedAuthorizedParty {
            guard jwt.payload.azp == expectedAzp else {
                throw JWTError.invalidAuthorizedParty(expected: expectedAzp, actual: jwt.payload.azp)
            }
        }
    }
    
    /// Convenience method to decode and validate in one step
    /// - Parameters:
    ///   - token: The JWT token string
    ///   - options: Validation options
    /// - Returns: A validated DecodedJWT
    /// - Throws: JWTError if decoding or validation fails
    public func decodeAndValidate(_ token: String, options: ValidationOptions) throws -> DecodedJWT {
        let jwt = try decode(token)
        try validate(jwt, options: options)
        return jwt
    }
    
    // MARK: - Private helpers
    
    private func base64URLDecode(_ string: String) throws -> Data {
        var base64 = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        
        // Add padding if needed
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        
        guard let data = Data(base64Encoded: base64) else {
            throw JWTError.invalidBase64
        }
        
        return data
    }
} 