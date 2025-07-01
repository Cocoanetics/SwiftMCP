import Foundation
import CryptoKit

/// A JSON Web Token (JWT) that can be decoded and signature-verified
public struct JSONWebToken: Sendable {
    
    /// The decoded JWT components
    public let header: JWTDecoder.JWTHeader
    public let payload: JWTDecoder.JWTPayload
    public let signature: String
    public let rawToken: String
    
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
    
    /// Errors that can occur during JWT operations
    public enum JWTError: Error, LocalizedError, Sendable {
        case invalidFormat
        case invalidBase64
        case invalidJSON
        case unsupportedAlgorithm
        case signatureVerificationFailed
        case jwksFetchFailed
        case keyNotFound
        case expired
        case notYetValid
        
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
            }
        }
    }
    
    /// Initialize a JWT from a token string
    /// - Parameter token: The JWT token string
    /// - Throws: JWTError if the token is malformed
    public init(token: String) throws {
        let segments = token.split(separator: ".")
        
        // Check for JWE format (5 segments: header.encrypted_key.iv.ciphertext.tag)
        if segments.count == 5 {
            throw JWTError.unsupportedAlgorithm
        }
        
        // Check for JWS format (3 segments: header.payload.signature)
        guard segments.count == 3 else {
            throw JWTError.invalidFormat
        }
        
        let headerData = try Self.base64URLDecode(String(segments[0]))
        let payloadData = try Self.base64URLDecode(String(segments[1]))
        let signature = String(segments[2])
        
        let header: JWTDecoder.JWTHeader
        let payload: JWTDecoder.JWTPayload
        
        do {
            header = try JSONDecoder().decode(JWTDecoder.JWTHeader.self, from: headerData)
        } catch {
            throw JWTError.invalidJSON
        }
        
        do {
            payload = try JSONDecoder().decode(JWTDecoder.JWTPayload.self, from: payloadData)
        } catch {
            throw JWTError.invalidJSON
        }
        
        self.header = header
        self.payload = payload
        self.signature = signature
        self.rawToken = token
    }
    
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
    
    /// Validate the JWT claims (exp, nbf, etc.) at a specific date
    /// - Parameter date: The date to validate against (defaults to current date)
    /// - Throws: JWTError if validation fails
    public func validateClaims(at date: Date = Date()) throws {
        // Check expiration
        if let exp = payload.exp {
            if date > exp {
                throw JWTError.expired
            }
        }
        
        // Check not before
        if let nbf = payload.nbf {
            if date < nbf {
                throw JWTError.notYetValid
            }
        }
    }
    
    /// Verify signature and validate claims in one step
    /// - Parameters:
    ///   - jwks: The JSON Web Key Set containing the public keys
    ///   - date: The date to validate against (defaults to current date)
    /// - Returns: True if both signature and claims are valid
    /// - Throws: JWTError if verification fails
    public func verify(using jwks: JWKS, at date: Date = Date()) throws -> Bool {
        // First validate claims
        try validateClaims(at: date)
        
        // Then verify signature
        return try verifySignature(using: jwks)
    }
    
    /// Fetch JWKS from the issuer and verify the token
    /// - Parameter issuer: The JWT issuer (used to construct JWKS URL)
    /// - Returns: True if the token is valid
    /// - Throws: JWTError if verification fails
    public func verify(using issuer: String) async throws -> Bool {
        let jwks = try await Self.fetchJWKS(from: issuer)
        return try verify(using: jwks)
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
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw JWTError.jwksFetchFailed
        }
        
        return try JSONDecoder().decode(JWKS.self, from: data)
    }
    
    // MARK: - Private helpers
    
    /// Verify RS256 signature using CryptoKit framework
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
        
        let headerAndPayload = "\(segments[0]).\(segments[1])"
        let signature = String(segments[2])
        
        // Decode the signature
        let signatureData = try base64URLDecode(signature)
        
        // Create RSA public key using X.509 certificate if available
        let publicKey = try createRSAPublicKeyFromJWK(
            modulus: publicKeyModulus,
            exponent: publicKeyExponent,
            x5c: x5c
        )
        
        // Create the data to verify
        let dataToVerify = headerAndPayload.data(using: .utf8)!
        
        // Verify the signature using CryptoKit
        return try verifyRS256SignatureWithCryptoKit(
            signature: signatureData,
            data: dataToVerify,
            publicKey: publicKey
        )
    }
    
    /// Create RSA public key from JWK parameters
    /// - Parameters:
    ///   - modulus: RSA modulus (base64url encoded)
    ///   - exponent: RSA exponent (base64url encoded)
    ///   - x5c: X.509 certificate chain (optional)
    /// - Returns: RSA public key
    /// - Throws: JWTError if key creation fails
    private static func createRSAPublicKeyFromJWK(
        modulus: String,
        exponent: String,
        x5c: [String]? = nil
    ) throws -> SecKey {
        if let x5c = x5c, let certB64 = x5c.first, let certData = Data(base64Encoded: certB64) {
            guard let certificate = SecCertificateCreateWithData(nil, certData as CFData) else {
                throw JWTError.signatureVerificationFailed
            }
            guard let publicKey = SecCertificateCopyKey(certificate) else {
                throw JWTError.signatureVerificationFailed
            }
            return publicKey
        }
        // Fallback to manual DER
        let modulusData = try base64URLDecode(modulus)
        let exponentData = try base64URLDecode(exponent)
        let derKey = createRSAPublicKeyDER(modulus: modulusData, exponent: exponentData)
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic
        ]
        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(derKey as CFData, attributes as CFDictionary, &error) else {
            throw JWTError.signatureVerificationFailed
        }
        return publicKey
    }
    
    /// Verify RS256 signature using CryptoKit
    /// - Parameters:
    ///   - signature: The signature to verify
    ///   - data: The data that was signed
    ///   - publicKey: The RSA public key
    /// - Returns: True if signature is valid
    /// - Throws: JWTError if verification fails
    private static func verifyRS256SignatureWithCryptoKit(
        signature: Data,
        data: Data,
        publicKey: SecKey
    ) throws -> Bool {
        // Use the correct algorithm for RS256
        let algorithm = SecKeyAlgorithm.rsaSignatureMessagePKCS1v15SHA256
        
        var error: Unmanaged<CFError>?
        let isValid = SecKeyVerifySignature(
            publicKey,
            algorithm,
            data as CFData, // Pass raw data, not hash
            signature as CFData,
            &error
        )
        
        if !isValid {
            throw JWTError.signatureVerificationFailed
        }
        
        return isValid
    }
    
    /// Create ASN.1 DER encoded RSA public key
    /// - Parameters:
    ///   - modulus: RSA modulus
    ///   - exponent: RSA exponent
    /// - Returns: DER encoded public key
    private static func createRSAPublicKeyDER(modulus: Data, exponent: Data) -> Data {
        // ASN.1 DER encoding for RSA public key
        // SEQUENCE {
        //   SEQUENCE {
        //     OBJECT IDENTIFIER rsaEncryption
        //     NULL
        //   }
        //   BIT STRING {
        //     SEQUENCE {
        //       INTEGER modulus
        //       INTEGER exponent
        //     }
        //   }
        // }
        
        var der = Data()
        
        // RSA OID: 1.2.840.113549.1.1.1
        let rsaOID: [UInt8] = [0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01]
        
        // Create the inner sequence (modulus, exponent)
        let innerSequence = createASN1Sequence([
            createASN1Integer(modulus),
            createASN1Integer(exponent)
        ])
        
        // Create the algorithm sequence (OID, NULL)
        let algorithmSequence = createASN1Sequence([
            Data(rsaOID),
            createASN1Null()
        ])
        
        // Create the bit string containing the inner sequence
        let bitString = createASN1BitString(innerSequence)
        
        // Create the outer sequence
        der = createASN1Sequence([algorithmSequence, bitString])
        
        return der
    }
    
    /// Create ASN.1 INTEGER
    /// - Parameter data: Integer data
    /// - Returns: ASN.1 encoded integer
    private static func createASN1Integer(_ data: Data) -> Data {
        var result = Data()
        
        // Add leading zero if needed to ensure positive number
        var value = data
        if value.first == 0x80 || (value.first == 0x00 && value.count > 1 && (value[1] & 0x80) == 0) {
            value.insert(0x00, at: 0)
        }
        
        result.append(0x02) // INTEGER tag
        result.append(contentsOf: encodeLength(value.count))
        result.append(value)
        
        return result
    }
    
    /// Create ASN.1 NULL
    /// - Returns: ASN.1 encoded NULL
    private static func createASN1Null() -> Data {
        return Data([0x05, 0x00]) // NULL tag, length 0
    }
    
    /// Create ASN.1 BIT STRING
    /// - Parameter data: Bit string data
    /// - Returns: ASN.1 encoded bit string
    private static func createASN1BitString(_ data: Data) -> Data {
        var result = Data()
        result.append(0x03) // BIT STRING tag
        result.append(contentsOf: encodeLength(data.count + 1))
        result.append(0x00) // Unused bits
        result.append(data)
        return result
    }
    
    /// Create ASN.1 SEQUENCE
    /// - Parameter items: Sequence items
    /// - Returns: ASN.1 encoded sequence
    private static func createASN1Sequence(_ items: [Data]) -> Data {
        var result = Data()
        let content = items.reduce(Data(), +)
        result.append(0x30) // SEQUENCE tag
        result.append(contentsOf: encodeLength(content.count))
        result.append(content)
        return result
    }
    
    /// Encode ASN.1 length
    /// - Parameter length: Length to encode
    /// - Returns: Length bytes
    private static func encodeLength(_ length: Int) -> [UInt8] {
        if length < 128 {
            return [UInt8(length)]
        } else {
            let bytes = withUnsafeBytes(of: length.bigEndian) { Data($0) }
            let significantBytes = bytes.drop(while: { $0 == 0 })
            return [UInt8(0x80 | significantBytes.count)] + Array(significantBytes)
        }
    }
    
    /// Base64URL decode
    /// - Parameter string: Base64URL encoded string
    /// - Returns: Decoded data
    /// - Throws: JWTError if decoding fails
    private static func base64URLDecode(_ string: String) throws -> Data {
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