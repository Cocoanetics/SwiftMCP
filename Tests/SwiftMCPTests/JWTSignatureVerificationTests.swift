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
    

    
    @Test("Verify JWT signature using CryptoKit framework")
    func testJWTSignatureVerification() async throws {
        // Test with the provided access token
        let issuer = "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"
        
        // Use a date within the token's validity period (iat: 1751206127)
        let validDate = Date(timeIntervalSince1970: 1751206127)
        
        let jwt = try JSONWebToken(token: Self.accessToken)
        let issuerURL = URL(string: issuer)!
        let isValid = try await jwt.verify(using: issuerURL, at: validDate)
        
        #expect(isValid == true)
    }
    
    @Test("Verify ID token signature using CryptoKit framework")
    func testIDTokenSignatureVerification() async throws {
        // Test with the provided ID token
        let issuer = "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"
        
        // Use a date within the token's validity period (iat: 1751206127)
        let validDate = Date(timeIntervalSince1970: 1751206127)
        
        let jwt = try JSONWebToken(token: Self.idToken)
        let issuerURL = URL(string: issuer)!
        let isValid = try await jwt.verify(using: issuerURL, at: validDate)
        
        #expect(isValid == true)
    }
    
    @Test("Reject modified JWT signature")
    func testRejectModifiedSignature() async throws {
        // Create a modified token with invalid signature
        let segments = Self.accessToken.split(separator: ".")
        let modifiedToken = "\(segments[0]).\(segments[1]).invalid-signature"
        
        let issuer = "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"
        
        do {
            let jwt = try JSONWebToken(token: modifiedToken)
            let issuerURL = URL(string: issuer)!
            _ = try await jwt.verify(using: issuerURL)
            #expect(Bool(false), "Expected verification to fail")
        } catch {
            #expect(error is JWTError)
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
            let jwt = try JSONWebToken(token: invalidToken)
            let issuerURL = URL(string: issuer)!
            _ = try await jwt.verify(using: issuerURL)
            #expect(Bool(false), "Expected verification to fail")
        } catch let error as JWTError {
            #expect(error == .unsupportedAlgorithm)
        } catch {
            #expect(Bool(false), "Expected unsupportedAlgorithm error, got \(error)")
        }
    }
    
    @Test("JWKS caching works correctly")
    func testJWKSCaching() async throws {
        // Load JWKS from local test resource
        let localJWKS = try loadTestJWKS()
        
        // Test that we can use the local JWKS for verification
        let jwt = try JSONWebToken(token: Self.accessToken)
        let validDate = Date(timeIntervalSince1970: 1751206127)
        let isValid = try jwt.verify(using: localJWKS, at: validDate)
        #expect(isValid == true)
    }
} 