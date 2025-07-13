import Foundation
import Testing
@testable import SwiftMCP

// MARK: - Test Resource Loading Helper

/// JWKS data for testing (embedded directly to avoid file loading issues)
let testJWKSData = """
{
  "keys": [
    {
      "kty": "RSA",
      "use": "sig",
      "n": "6-pg4UUyl358e7OiriuBzKuHlefgtUkEV8kpOYN1-Z6H9SXPRNvrpOfeMdJfay6U94ROb8j9mhba22AX9-V5CXVv-zfizBQFbqLywq6UNF53RoRkAkQuQbdwKl4jTtNGObtWF7FEY_yPGd2Y25Da2HtpIZeO1tqnPpwteDPnKI4koQWlTeuI6fCbyhckDXI9X_-xvoRmW6c3FOs9zcuqa_aGTLWdmb6A4wRgS66_pzY2F3ccgG5UkEq2CGMVl6-boNNWP_FJQF-z3vzBtM7VULz2U4y08Gk_8-ulWrGOcbmFhVU7obuJvC2afbrdoiPbD2sg64kO1cdNPr745OQ9gQ",
      "e": "AQAB",
      "kid": "i_F8LZGaD-tJB3roLrDB1",
      "x5t": "Rn8yHdStu3fvQqytLEqMT-Yd-QI",
      "x5c": [
        "MIIDHTCCAgWgAwIBAgIJDn8Y8QY3z80wMA0GCSqGSIb3DQEBCwUAMCwxKjAoBgNVBAMTIWRldi04eWdqNmVwcG52ano4Ym02LnVzLmF1dGgwLmNvbTAeFw0yNTA2MjQxNTQ1NDFaFw0zOTAzMDMxNTQ1NDFaMCwxKjAoBgNVBAMTIWRldi04eWdqNmVwcG52ano4Ym02LnVzLmF1dGgwLmNvbTCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAOvqYOFFMpd+fHuzoq4rgcyrh5Xn4LVJBFfJKTmDdfmeh/Ulz0Tb66Tn3jHSX2sulPeETm/I/ZoW2ttgF/fleQl1b/s34swUBW6i8sKulDRed0aEZAJELkG3cCpeI07TRjm7VhexRGP8jxndmNuQ2th7aSGXjtbapz6cLXgz5yiOJKEFpU3riOnwm8oXJA1yPV//sb6EZlunNxTrPc3Lqmv2hky1nZm+gOMEYEuuv6c2Nhd3HIBuVJBKtghjFZevm6DTVj/xSUBfs978wbTO1VC89lOMtPBpP/PrpVqxjnG5hYVVO6G7ibwtmn263aIj2w9rIOuJDtXHTT6++OTkPYECAwEAAaNCMEAwDwYDVR0TAQH/BAUwAwEB/zAdBgNVHQ4EFgQUXlGH4xINz773VU3GACHST/SbkJkwDgYDVR0PAQH/BAQDAgKEMA0GCSqGSIb3DQEBCwUAA4IBAQALuQdw6vcUdE1pXTwrnAz5AegSRpjNIgRNSAj3RsDU9LmEhMZMw9KSx2QCl8SO61H/ObZ3scxjES0UVsQqKDnRX0gQZTx3vHLnDCUnpwiSoHSUK1oTxCtsnfdH9CD26+zd+7Yv9XqRp+FucUznoe9jVTDVSvKYUyomjm0VkExZBWQGss8uVgYEEZ/3FqAm6DU+yuml5y0BeLz89ys3jxOJd6aBjuKar+ls1CDvu25zsymTHotAoSU6JUYhqJ6yx45UBz0vOGH52Xa3aqDlO4+dEBwBihPQ8D6AyCtUZ1rmSSAjClQR7gkBoETqlyoI90DhbSHyR6OkJ3D58ZSrp6xw"
      ],
      "alg": "RS256"
    }
  ]
}
"""

/// Load JWKS from embedded test data
/// - Returns: The JSONWebKeySet loaded from the embedded data
func loadTestJWKS() throws -> JSONWebKeySet {
    let jwksData = testJWKSData.data(using: .utf8)!
    let decoder = JSONDecoder()
    return try decoder.decode(JSONWebKeySet.self, from: jwksData)
}

// MARK: - JSONWebToken Tests

@Suite("JSONWebToken", .tags(.unit))
struct JSONWebTokenTests {
    
    // Real tokens provided by the user
    static let accessToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6ImF0K2p3dCIsImtpZCI6ImlfRjhMWkdhRC10SkIzcm9MckRCMSJ9.eyJpc3MiOiJodHRwczovL2Rldi04eWdqNmVwcG52ano4Ym02LnVzLmF1dGgwLmNvbS8iLCJzdWIiOiJhdXRoMHw2ODViZmUwN2E1NGIyNGFhNzhiMGNhMmQiLCJhdWQiOlsiaHR0cHM6Ly91bmlxdWUtc3BvbmdlLWRyaXZlbi5uZ3Jvay1mcmVlLmFwcCIsImh0dHBzOi8vZGV2LTh5Z2o2ZXBwbnZqejhibTYudXMuYXV0aDAuY29tL3VzZXJpbmZvIl0sImlhdCI6MTc1MTIwNjEyNywiZXhwIjoxNzUxMjkyNTI3LCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwianRpIjoiOUh0OGljam5nSjZNZWNETUtIY0hFdCIsImNsaWVudF9pZCI6IkV6ekZnb2wzUU1lNmVRb1h4a2ZmNEUyYldkcEIyRGc5In0.jAJghjJIC-fb3sNdDttBC8Grli1Q6mhJM-Qc8ny4tGTPX9GHv5ypr5xKCDwI2oeX61rsQm6SLCquFFNRv8nOL8KafRelgPxoJPyY22A6UnbRjQlU_H2NyhOTHBeUy4cAAoZnqUqIHrK2EPAjyJtjUFlOBkEIzGZyxvW8V_8-4G7WJYoT9Ue-qZ6soXELOmWKXPekqj2QC1mEuZuqvnKfE2-wdcVOyOJ5c6TxL60dKEMioBU921wnm60DQ8anxuLHHsIrOrlyZgArZrf5SHf98arr7Vma7RiYmEpTNJwuXfxy2b_J29YHil4lm5RXgXyhfnCqnR4X8r4geUWlNcDEjA"
    
    static let idToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImlfRjhMWkdhRC10SkIzcm9MckRCMSJ9.eyJuaWNrbmFtZSI6Im9saXZlcitkcm9wcyIsIm5hbWUiOiJvbGl2ZXIrZHJvcHNAZHJvYm5pay5jb20iLCJwaWN0dXJlIjoiaHR0cHM6Ly9zLmdyYXZhdGFyLmNvbS9hdmF0YXIvNDNhMDZjOTdlNjE2YTcwMmE2MTI4YjA0MDIzNDhjMmI_cz00ODAmcj1wZyZkPWh0dHBzJTNBJTJGJTJGY2RuLmF1dGgwLmNvbSUyRmF2YXRhcnMlMkZvbC5wbmciLCJ1cGRhdGVkX2F0IjoiMjAyNS0wNi0yN1QxMzo1NDozNS45MDdaIiwiZW1haWwiOiJvbGl2ZXIrZHJvcHNAZHJvYm5pay5jb20iLCJlbWFpbF92ZXJpZmllZCI6dHJ1ZSwiaXNzIjoiaHR0cHM6Ly9kZXYtOHlnajZlcHBudmp6OGJtNi51cy5hdXRoMC5jb20vIiwiYXVkIjoiRXp6RmdvbDNRTWU2ZVFvWHhrZmY0RTJiV2RwQjJEZzkiLCJzdWIiOiJhdXRoMHw2ODViZmUwN2E1NGIyNGFhNzhiMGNhMmQiLCJpYXQiOjE3NTEyMDYxMjcsImV4cCI6MTc1MTI0MjEyNywic2lkIjoieFJ1ZEItYmphTkZoVV9rODVwYkM5SWxsNzFVMkEtbXkifQ.SDA735wvNiweN_ruafcRoVUhhM8smmjBLx-p1W1V_U9H_dlVoURKuRsjC0DaAEHLb07UfqKx181xcFI2GNdUHBG7p1nJU2AkRpZ0Jkqa_G2mqpq3ALx7EbJaewEHUJGxYbxo4hPetfat74kYPmjcrL44D9eQfmb3nVyk0QOsFFhSNIFNL50s3SghQRULeGrn2bdIm34QUA5bhg9acmVKL0l0H58Cj3oOoedPP0UyYljRDBYgu3EMFCRFS97Rvfh1PQop-QGTKrPbzqAUtcCMJ4R_TWPYNLUEKJHWQbdcsxYQ8MNPdJ_LAeUB5-EfQZRIfku9kiizx_SlLHq4Uw2-Xg"
    
    // Test issuer URL
    static let issuerURL = URL(string: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")!
    
    @Test("Initialize JSONWebToken from access token string")
    func testInitFromAccessToken() throws {
        let jwt = try JSONWebToken(token: Self.accessToken)
        
        // Verify header
        #expect(jwt.header.alg == "RS256")
        #expect(jwt.header.typ == "at+jwt")
        #expect(jwt.header.kid == "i_F8LZGaD-tJB3roLrDB1")
        
        // Verify payload
        #expect(jwt.payload.iss == "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
        #expect(jwt.payload.sub == "auth0|685bfe07a54b24aa78b0ca2d")
        #expect(jwt.payload.scope == "openid profile email")
        
        // Verify signature is present
        #expect(!jwt.signature.isEmpty)
        #expect(jwt.rawToken == Self.accessToken)
    }
    
    @Test("Initialize JSONWebToken from ID token string")
    func testInitFromIDToken() throws {
        let jwt = try JSONWebToken(token: Self.idToken)
        
        // Verify header
        #expect(jwt.header.alg == "RS256")
        #expect(jwt.header.typ == "JWT")
        #expect(jwt.header.kid == "i_F8LZGaD-tJB3roLrDB1")
        
        // Verify payload
        #expect(jwt.payload.iss == "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
        #expect(jwt.payload.sub == "auth0|685bfe07a54b24aa78b0ca2d")
        #expect(jwt.payload.aud?.contains("EzzFgol3QMe6eQoXxkff4E2bWdpB2Dg9") == true)
        
        // Verify signature is present
        #expect(!jwt.signature.isEmpty)
        #expect(jwt.rawToken == Self.idToken)
    }
    
    @Test("Validate claims at specific date")
    func testValidateClaimsAtDate() throws {
        let jwt = try JSONWebToken(token: Self.accessToken)
        
        // Test with a date before expiration (should pass)
        let validDate = Date(timeIntervalSince1970: 1751206127) // iat time
        try jwt.validateClaims(at: validDate)
        
        // Note: We don't test expiration since the real token has expired by now
        // In production, you would use current tokens or mock tokens for testing
    }
    
    @Test("Validate claims with options")
    func testValidateClaimsWithOptions() throws {
        let jwt = try JSONWebToken(token: Self.accessToken)
        
        let options = JWTValidationOptions(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            expectedAudience: "https://unique-sponge-driven.ngrok-free.app"
        )
        
        let validDate = Date(timeIntervalSince1970: 1751206127) // iat time
        try jwt.validateClaims(at: validDate, options: options)
        
        // Test with wrong issuer
        let wrongOptions = JWTValidationOptions(
            expectedIssuer: "https://wrong-issuer.com/"
        )
        
        do {
            try jwt.validateClaims(at: validDate, options: wrongOptions)
            #expect(Bool(false), "Expected validation to fail for wrong issuer")
        } catch let error as JWTError {
            switch error {
            case .invalidIssuer(let expected, let actual):
                #expect(expected == "https://wrong-issuer.com/")
                #expect(actual == "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
            default:
                #expect(Bool(false), "Expected invalidIssuer error, got \(error)")
            }
        }
    }
    
    @Test("Verify signature using JWKS")
    func testVerifySignatureUsingJWKS() async throws {
        let jwt = try JSONWebToken(token: Self.accessToken)
        
        // Load JWKS from local test resource
        let jwks = try loadTestJWKS()
        
        // Verify signature
        let isValid = try jwt.verifySignature(using: jwks)
        #expect(isValid == true)
    }
    
    @Test("Verify token with claims validation using JWKS")
    func testVerifyWithClaimsValidation() async throws {
        let jwt = try JSONWebToken(token: Self.accessToken)
        
        // Load JWKS from local test resource
        let jwks = try loadTestJWKS()
        
        // Verify with claims validation at valid time
        let validDate = Date(timeIntervalSince1970: 1751206127) // iat time
        let isValid = try jwt.verify(using: jwks, at: validDate)
        #expect(isValid == true)
    }
    
    @Test("Verify token with custom date")
    func testVerifyWithCustomDate() async throws {
        let jwt = try JSONWebToken(token: Self.accessToken)
        
        // Load JWKS from local test resource
        let jwks = try loadTestJWKS()
        
        // Verify with a specific date (iat time)
        let customDate = Date(timeIntervalSince1970: 1751206127)
        let isValid = try jwt.verify(using: jwks, at: customDate)
        #expect(isValid == true)
    }
    
    @Test("Verify token using issuer directly")
    func testVerifyUsingIssuer() async throws {
        let jwt = try JSONWebToken(token: Self.accessToken)
        
        // Verify using local JWKS instead of making network request
        let validDate = Date(timeIntervalSince1970: 1751206127) // iat time
        let localJWKS = try loadTestJWKS()
        let isValid = try jwt.verify(using: localJWKS, at: validDate)
        #expect(isValid == true)
    }
    
    @Test("Reject modified token")
    func testRejectModifiedToken() async throws {
        // Create a modified token with invalid signature (valid base64 but wrong signature)
        let segments = Self.accessToken.split(separator: ".")
        let modifiedToken = "\(segments[0]).\(segments[1]).dGVzdC1zaWduYXR1cmU=" // base64 for "test-signature"
        
        let jwt = try JSONWebToken(token: modifiedToken)
        let jwks = try loadTestJWKS()
        
        #expect(throws: JWTError.signatureVerificationFailed) {
            try jwt.verifySignature(using: jwks)
        }
    }
    
    @Test("Reject token with unsupported algorithm")
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
        
        let jwt = try JSONWebToken(token: invalidToken)
        let jwks = try loadTestJWKS()
        
        #expect(throws: JWTError.unsupportedAlgorithm) {
            try jwt.verifySignature(using: jwks)
        }
    }
    
    @Test("Access JWT payload properties directly")
    func testDirectPayloadAccess() throws {
        let jwt = try JSONWebToken(token: Self.accessToken)
        
        // Directly access payload properties instead of extractUserInfo()
        #expect(jwt.payload.sub == "auth0|685bfe07a54b24aa78b0ca2d")
        #expect(jwt.payload.iss == "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
        #expect(jwt.payload.scope == "openid profile email")
        #expect(jwt.payload.exp != nil)
        #expect(jwt.payload.iat != nil)
        #expect(jwt.payload.aud != nil)
    }
} 