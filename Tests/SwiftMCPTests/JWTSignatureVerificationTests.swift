import Foundation
import Testing
import Crypto
import _CryptoExtras
import X509
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import SwiftMCP

@Suite("JWT Signature Verification", .tags(.unit))
struct JWTSignatureVerificationTests {
    
    // Real tokens provided by the user
    static let accessToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6ImF0K2p3dCIsImtpZCI6ImlfRjhMWkdhRC10SkIzcm9MckRCMSJ9.eyJpc3MiOiJodHRwczovL2Rldi04eWdqNmVwcG52ano4Ym02LnVzLmF1dGgwLmNvbS8iLCJzdWIiOiJhdXRoMHw2ODViZmUwN2E1NGIyNGFhNzhiMGNhMmQiLCJhdWQiOlsiaHR0cHM6Ly91bmlxdWUtc3BvbmdlLWRyaXZlbi5uZ3Jvay1mcmVlLmFwcCIsImh0dHBzOi8vZGV2LTh5Z2o2ZXBwbnZqejhibTYudXMuYXV0aDAuY29tL3VzZXJpbmZvIl0sImlhdCI6MTc1MTIwNjEyNywiZXhwIjoxNzUxMjkyNTI3LCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwianRpIjoiOUh0OGljam5nSjZNZWNETUtIY0hFdCIsImNsaWVudF9pZCI6IkV6ekZnb2wzUU1lNmVRb1h4a2ZmNEUyYldkcEIyRGc5In0.jAJghjJIC-fb3sNdDttBC8Grli1Q6mhJM-Qc8ny4tGTPX9GHv5ypr5xKCDwI2oeX61rsQm6SLCquFFNRv8nOL8KafRelgPxoJPyY22A6UnbRjQlU_H2NyhOTHBeUy4cAAoZnqUqIHrK2EPAjyJtjUFlOBkEIzGZyxvW8V_8-4G7WJYoT9Ue-qZ6soXELOmWKXPekqj2QC1mEuZuqvnKfE2-wdcVOyOJ5c6TxL60dKEMioBU921wnm60DQ8anxuLHHsIrOrlyZgArZrf5SHf98arr7Vma7RiYmEpTNJwuXfxy2b_J29YHil4lm5RXgXyhfnCqnR4X8r4geUWlNcDEjA"
    
    static let idToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImlfRjhMWkdhRC10SkIzcm9MckRCMSJ9.eyJuaWNrbmFtZSI6Im9saXZlcitkcm9wcyIsIm5hbWUiOiJvbGl2ZXIrZHJvcHNAZHJvYm5pay5jb20iLCJwaWN0dXJlIjoiaHR0cHM6Ly9zLmdyYXZhdGFyLmNvbS9hdmF0YXIvNDNhMDZjOTdlNjE2YTcwMmE2MTI4YjA0MDIzNDhjMmI_cz00ODAmcj1wZyZkPWh0dHBzJTNBJTJGJTJGY2RuLmF1dGgwLmNvbSUyRmF2YXRhcnMlMkZvbC5wbmciLCJ1cGRhdGVkX2F0IjoiMjAyNS0wNi0yN1QxMzo1NDozNS45MDdaIiwiZW1haWwiOiJvbGl2ZXIrZHJvcHNAZHJvYm5pay5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiaXNzIjoiaHR0cHM6Ly9kZXYtOHlnajZlcHBudmp6OGJtNi51cy5hdXRoMC5jb20vIiwiYXVkIjoiRXp6RmdvbDNRTWU2ZVFvWHhrZmY0RTJiV2RwQjJEZzkiLCJzdWIiOiJhdXRoMHw2ODViZmUwN2E1NGIyNGFhNzhiMGNhMmQiLCJpYXQiOjE3NTEyMDYxMjcsImV4cCI6MTc1MTI0MjEyNywic2lkIjoieFJ1ZEItYmphTkZoVV9rODVwYkM5SWxsNzFVMkEtbXkifQ.SDA735wvNiweN_ruafcRoVUhhM8smmjBLx-p1W1V_U9H_dlVoURKuRsjC0DaAEHLb07UfqKx181xcFI2GNdUHBG7p1nJU2AkRpZ0Jkqa_G2mqpq3ALx7EbJaewEHUJGxYbxo4hPetfat74kYPmjcrL44D9eQfmb3nVyk0QOsFFhSNIFNL50s3SghQRULeGrn2bdIm34QUA5bhg9acmVKL0l0H58Cj3oOoedPP0UyYljRDBYgu3EMFCRFS97Rvfh1PQop-QGTKrPbzqAUtcCMJ4R_TWPYNLUEKJHWQbdcsxYQ8MNPdJ_LAeUB5-EfQZRIfku9kiizx_SlLHq4Uw2-Xg"
    
    // JWKS response structure
    struct JWKSResponse: Codable {
        let keys: [JWK]
    }
    
    struct JWK: Codable {
        let kty: String
        let kid: String
        let use: String?
        let alg: String?
        let n: String  // RSA modulus
        let e: String  // RSA exponent
        let x5c: [String]?  // X.509 certificate chain
    }
    
    // JWT Signature Verifier using CryptoKit framework
    struct JWTSignatureVerifier {
        
        enum VerificationError: Error, LocalizedError {
            case invalidAlgorithm
            case unsupportedAlgorithm
            case invalidKeyFormat
            case signatureVerificationFailed
            case jwksFetchFailed
            case keyNotFound
            
            var errorDescription: String? {
                switch self {
                case .invalidAlgorithm:
                    return "Invalid or unsupported JWT algorithm"
                case .unsupportedAlgorithm:
                    return "Algorithm not supported for signature verification"
                case .invalidKeyFormat:
                    return "Invalid key format"
                case .signatureVerificationFailed:
                    return "JWT signature verification failed"
                case .jwksFetchFailed:
                    return "Failed to fetch JWKS from issuer"
                case .keyNotFound:
                    return "Key with specified kid not found in JWKS"
                }
            }
        }
        
        /// Verify JWT signature using public key from JWKS
        /// - Parameters:
        ///   - token: The JWT token to verify
        ///   - issuer: The JWT issuer (used to construct JWKS URL)
        /// - Returns: True if signature is valid
        /// - Throws: VerificationError if verification fails
        static func verifySignature(token: String, issuer: String) async throws -> Bool {
            // Decode the JWT to get header and payload
            let jwt = try JSONWebToken(token: token)
            
            // Check algorithm
            guard jwt.header.alg == "RS256" else {
                throw VerificationError.unsupportedAlgorithm
            }
            
            // Get the key ID
            guard let kid = jwt.header.kid else {
                throw VerificationError.invalidKeyFormat
            }
            
            // Fetch JWKS from issuer
            let jwks = try await fetchJWKS(from: issuer)
            
            // Find the key with matching kid
            guard let jwk = jwks.keys.first(where: { $0.kid == kid }) else {
                throw VerificationError.keyNotFound
            }
            
            // Verify the signature
            return try verifyRS256Signature(
                token: token,
                publicKeyModulus: jwk.n,
                publicKeyExponent: jwk.e,
                x5c: jwk.x5c
            )
        }
        
        /// Fetch JWKS from the issuer
        /// - Parameter issuer: The JWT issuer
        /// - Returns: JWKS response
        /// - Throws: VerificationError if fetch fails
        private static func fetchJWKS(from issuer: String) async throws -> JWKSResponse {
            let jwksURL = "\(issuer).well-known/jwks.json"
            
            guard let url = URL(string: jwksURL) else {
                throw VerificationError.jwksFetchFailed
            }
            
            #if canImport(FoundationNetworking)
            // For Linux/cross-platform environments, use FoundationNetworking
            return try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    if let error = error {
                        continuation.resume(throwing: VerificationError.jwksFetchFailed)
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse,
                          httpResponse.statusCode == 200,
                          let data = data else {
                        continuation.resume(throwing: VerificationError.jwksFetchFailed)
                        return
                    }
                    
                    do {
                        let jwks = try JSONDecoder().decode(JWKSResponse.self, from: data)
                        continuation.resume(returning: jwks)
                    } catch {
                        continuation.resume(throwing: VerificationError.jwksFetchFailed)
                    }
                }
                task.resume()
            }
            #else
            // For Darwin/macOS/iOS environments, use standard URLSession
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw VerificationError.jwksFetchFailed
            }
            
            return try JSONDecoder().decode(JWKSResponse.self, from: data)
            #endif
        }
        
        /// Verify RS256 signature using CryptoKit framework
        /// - Parameters:
        ///   - token: The JWT token
        ///   - publicKeyModulus: RSA modulus (base64url encoded)
        ///   - publicKeyExponent: RSA exponent (base64url encoded)
        ///   - x5c: X.509 certificate chain (optional)
        /// - Returns: True if signature is valid
        /// - Throws: VerificationError if verification fails
        private static func verifyRS256Signature(
            token: String,
            publicKeyModulus: String,
            publicKeyExponent: String,
            x5c: [String]? = nil
        ) throws -> Bool {
            // Split the token
            let segments = token.split(separator: ".")
            guard segments.count == 3 else {
                throw VerificationError.invalidKeyFormat
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
        
        /// Create RSA public key from JWK parameters using Swift Crypto
        /// - Parameters:
        ///   - modulus: RSA modulus (base64url encoded)
        ///   - exponent: RSA exponent (base64url encoded)
        ///   - x5c: X.509 certificate chain (optional)
        /// - Returns: RSA.Signing.PublicKey from Swift Crypto
        /// - Throws: VerificationError if key creation fails
        private static func createRSAPublicKeyFromJWK(
            modulus: String,
            exponent: String,
            x5c: [String]? = nil
        ) throws -> _RSA.Signing.PublicKey {
            // For now, focus on manual key construction from modulus/exponent
            // TODO: Add X.509 certificate parsing when swift-certificates API is stable
            
            // Create key from modulus / exponent in the JWKS
            let modulusData = try base64URLDecode(modulus)
            let exponentData = try base64URLDecode(exponent)
            
            return try _RSA.Signing.PublicKey(n: modulusData, e: exponentData)
        }
        
        /// Verify RS256 signature using Swift Crypto
        /// - Parameters:
        ///   - signature: The signature to verify
        ///   - data: The data that was signed
        ///   - publicKey: The RSA public key from Swift Crypto
        /// - Returns: True if signature is valid
        /// - Throws: VerificationError if verification fails
        private static func verifyRS256SignatureWithCryptoKit(
            signature: Data,
            data: Data,
            publicKey: _RSA.Signing.PublicKey
        ) throws -> Bool {
            // Verify the signature using Swift Crypto
            do {
                let rsaSignature = _RSA.Signing.RSASignature(rawRepresentation: signature)
                let isValid = publicKey.isValidSignature(rsaSignature, for: data, padding: .insecurePKCS1v1_5)
                
                if !isValid {
                    throw VerificationError.signatureVerificationFailed
                }
                
                return true
            } catch {
                // If signature creation or verification fails, it's an invalid signature
                throw VerificationError.signatureVerificationFailed
            }
        }
        

        
        /// Base64URL decode
        /// - Parameter string: Base64URL encoded string
        /// - Returns: Decoded data
        /// - Throws: VerificationError if decoding fails
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
                throw VerificationError.invalidKeyFormat
            }
            
            return data
        }
    }
    
    @Test("Verify JWT signature using CryptoKit framework")
    func testJWTSignatureVerification() async throws {
        // Test with the provided access token
        let issuer = "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"
        
        let isValid = try await JWTSignatureVerifier.verifySignature(
            token: Self.accessToken,
            issuer: issuer
        )
        
        #expect(isValid == true)
    }
    
    @Test("Verify ID token signature using CryptoKit framework")
    func testIDTokenSignatureVerification() async throws {
        // Test with the provided ID token
        let issuer = "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"
        
        let isValid = try await JWTSignatureVerifier.verifySignature(
            token: Self.idToken,
            issuer: issuer
        )
        
        #expect(isValid == true)
    }
    
    @Test("Reject modified JWT signature")
    func testRejectModifiedSignature() async throws {
        // Create a modified token with invalid signature
        let segments = Self.accessToken.split(separator: ".")
        let modifiedToken = "\(segments[0]).\(segments[1]).invalid-signature"
        
        let issuer = "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"
        
        do {
            _ = try await JWTSignatureVerifier.verifySignature(
                token: modifiedToken,
                issuer: issuer
            )
            #expect(Bool(false), "Expected verification to fail")
        } catch {
            #expect(error is JWTSignatureVerifier.VerificationError)
        }
    }
    
    @Test("Reject JWT with unsupported algorithm")
    func testRejectUnsupportedAlgorithm() async throws {
        // Create a token with unsupported algorithm
        let header = """
        {
            "alg": "HS256",
            "typ": "JWT"
        }
        """
        let payload = """
        {
            "iss": "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            "sub": "test",
            "exp": 2524608000
        }
        """
        
        let headerB64 = Data(header.data(using: .utf8)!).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let payloadB64 = Data(payload.data(using: .utf8)!).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        
        let invalidToken = "\(headerB64).\(payloadB64).signature"
        
        let issuer = "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"
        
        do {
            _ = try await JWTSignatureVerifier.verifySignature(
                token: invalidToken,
                issuer: issuer
            )
            #expect(Bool(false), "Expected verification to fail")
        } catch let error as JWTSignatureVerifier.VerificationError {
            #expect(error == .unsupportedAlgorithm)
        } catch {
            #expect(Bool(false), "Expected unsupportedAlgorithm error, got \(error)")
        }
    }
} 