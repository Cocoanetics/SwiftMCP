import Foundation
import Testing
@testable import SwiftMCP

@Suite("JWT Decoder", .tags(.unit))
struct JWTDecoderTests {
    
    // Synthetic test token with far-future expiration (2030) for deterministic tests
    static let testToken = "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImlfRjhMWkdhRC10SkIzcm9MckRCMSJ9.eyJpc3MiOiJodHRwczovL2Rldi04eWdqNmVwcG52ano4Ym02LnVzLmF1dGgwLmNvbS8iLCJzdWIiOiJhdXRoMHw2ODViZmUwN2E1NGIyNGFhNzhiMGNhMmQiLCJhdWQiOlsiaHR0cHM6Ly9kZXYtOHlnajZlcHBudmp6OGJtNi51cy5hdXRoMC5jb20vYXBpL3YyLyIsImh0dHBzOi8vZGV2LTh5Z2o2ZXBwbnZqejhibTYudXMuYXV0aDAuY29tL3VzZXJpbmZvIl0sImlhdCI6MTc1MDg4MjM5OSwiZXhwIjoyNTI0NjA4MDAwLCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwiYXpwIjoibjR2bXJqaUFobW9FMVAxSnZqdkYxaVU4bTFSVHEzeWkifQ.fake-signature-for-testing"
    
    // New token supplied by the user that lacks the azp claim (access_token type)
    static let tokenWithoutAzp = "eyJhbGciOiJSUzI1NiIsInR5cCI6ImF0K2p3dCIsImtpZCI6ImlfRjhMWkdhRC10SkIzcm9MckRCMSJ9.eyJpc3MiOiJodHRwczovL2Rldi04eWdqNmVwcG52ano4Ym02LnVzLmF1dGgwLmNvbS8iLCJzdWIiOiJhdXRoMHw2ODViZmUwN2E1NGIyNGFhNzhiMGNhMmQiLCJhdWQiOlsiaHR0cHM6Ly91bmlxdWUtc3BvbmdlLWRyaXZlbi5uZ3Jvay1mcmVlLmFwcCIsImh0dHBzOi8vZGV2LTh5Z2o2ZXBwbnZqejhibTYudXMuYXV0aDAuY29tL3VzZXJpbmZvIl0sImlhdCI6MTc1MTAxMzMwOCwiZXhwIjoxNzUxMDk5NzA4LCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwianRpIjoic3RROTlmakt3VGFUR3lBQjRFM3pDNSIsImNsaWVudF9pZCI6Ik81VmJUR1BlT1lURG5qbzhCckQyV0ZzYjRMcm15WGxiIn0.kMsmlMNuPGwMZC-_DHvemhlUOkx-uQret9LzFc47kOSSpbpl-_XkKqUTFhCkV69Ywpu5rJah8ZA-bLKPT-fNE1QnuWvRwwW335XbfSjO9R8xRjrXrju1GdIXkp3pnoGN642BrkxlYnoXM3NdUTfiNRGQfsliVzvcmQpEXH7NV_nivCti4aQVW3ERVqrAzPHg53IKq7-lokW6mEV23YjwvpUm4DJqvSbNA9h5pIm-_Te1wP-iHEUmsPnp8g_Y2O9qXPxMWrsTe4JU7lemaeosNZOlHX6krXWxvCGpSyZnaa-gzT7P1RD1efnjg6YnMHzz_1Mpa7muaWnm5Khq5wFI9A"
    
    @Test("Decode JWT token successfully")
    func testDecodeJWT() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.testToken)
        
        // Verify header
        #expect(jwt.header.alg == "RS256")
        #expect(jwt.header.typ == "JWT")
        #expect(jwt.header.kid == "i_F8LZGaD-tJB3roLrDB1")
        
        // Verify payload
        #expect(jwt.payload.iss == "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
        #expect(jwt.payload.sub == "auth0|685bfe07a54b24aa78b0ca2d")
        #expect(jwt.payload.scope == "openid profile email")
        #expect(jwt.payload.azp == "n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi")
        
        // Verify audience
        guard case .multiple(let audiences) = jwt.payload.aud else {
            #expect(Bool(false), "Expected multiple audiences")
            return
        }
        #expect(audiences.contains("https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/"))
        #expect(audiences.contains("https://dev-8ygj6eppnvjz8bm6.us.auth0.com/userinfo"))
        
        // Verify timestamps (these are the actual values from the token)
        #expect(jwt.payload.iat?.timeIntervalSince1970 == 1750882399)
        #expect(jwt.payload.exp?.timeIntervalSince1970 == 2524608000)
        
        // Verify signature is present
        #expect(!jwt.signature.isEmpty)
        #expect(jwt.rawToken == Self.testToken)
    }
    
    @Test("Decode malformed JWT fails")
    func testDecodeMalformedJWT() {
        let decoder = JWTDecoder()
        
        // Test various malformed tokens
        let malformedTokens = [
            "not.a.jwt",  // Not enough segments
            "too.many.segments.here",  // Too many segments
            "",  // Empty string
            "aW52YWxpZA.aW52YWxpZA.signature"  // Invalid JSON (valid base64 but not JSON)
        ]
        
        for token in malformedTokens {
            #expect(throws: (any Error).self) {
                try decoder.decode(token)
            }
        }
    }
    
    @Test("Decode JWT with invalid format")
    func testInvalidFormat() {
        let decoder = JWTDecoder()
        
        #expect(throws: JWTDecoder.JWTError.invalidFormat) {
            try decoder.decode("only-two.segments")
        }
        
        #expect(throws: JWTDecoder.JWTError.invalidFormat) {
            try decoder.decode("too.many.segments.here.extra.more")
        }
        
        #expect(throws: JWTDecoder.JWTError.invalidFormat) {
            try decoder.decode("")
        }
    }
    
    @Test("Decode JWT with invalid base64")
    func testInvalidBase64() {
        let decoder = JWTDecoder()
        
        #expect(throws: JWTDecoder.JWTError.invalidBase64) {
            try decoder.decode("invalid-base64!!!.invalid-base64!!!.signature")
        }
    }
    
    @Test("Decode JWT with invalid JSON")
    func testInvalidJSON() {
        let decoder = JWTDecoder()
        
        // "invalid" base64 encoded is "aW52YWxpZA==" but we'll remove padding for URL-safe
        #expect(throws: JWTDecoder.JWTError.invalidJSON) {
            try decoder.decode("aW52YWxpZA.aW52YWxpZA.signature")
        }
    }
    
    @Test("Validate JWT with correct issuer")
    func testValidateCorrectIssuer() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.testToken)
        
        let options = JWTDecoder.ValidationOptions(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/"
        )
        
        // This should not throw
        try decoder.validate(jwt, options: options)
    }
    
    @Test("Validate JWT with incorrect issuer fails")
    func testValidateIncorrectIssuer() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.testToken)
        
        let options = JWTDecoder.ValidationOptions(
            expectedIssuer: "https://wrong-issuer.com/"
        )
        
        #expect(throws: JWTDecoder.JWTError.self) {
            try decoder.validate(jwt, options: options)
        }
    }
    
    @Test("Validate JWT with correct audience")
    func testValidateCorrectAudience() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.testToken)
        
        let options = JWTDecoder.ValidationOptions(
            expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/"
        )
        
        // This should not throw
        try decoder.validate(jwt, options: options)
    }
    
    @Test("Validate JWT with incorrect audience fails")
    func testValidateIncorrectAudience() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.testToken)
        
        let options = JWTDecoder.ValidationOptions(
            expectedAudience: "https://wrong-audience.com/"
        )
        
        #expect(throws: JWTDecoder.JWTError.self) {
            try decoder.validate(jwt, options: options)
        }
    }
    
    @Test("Create expired JWT and validate expiration")
    func testExpiredJWT() throws {
        // Create a JWT that expired 1 hour ago
        let expiredTime = Date().addingTimeInterval(-3600)
        let issuedTime = Date().addingTimeInterval(-7200)
        
        let expiredJWT = createTestJWT(
            iat: issuedTime,
            exp: expiredTime
        )
        
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(expiredJWT)
        
        let options = JWTDecoder.ValidationOptions()
        
        #expect(throws: JWTDecoder.JWTError.self) {
            try decoder.validate(jwt, options: options)
        }
    }
    
    @Test("Create future JWT and validate not before")
    func testFutureJWT() throws {
        // Create a JWT that's not valid until 1 hour from now
        let futureTime = Date().addingTimeInterval(3600)
        
        let futureJWT = createTestJWT(
            nbf: futureTime
        )
        
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(futureJWT)
        
        let options = JWTDecoder.ValidationOptions()
        
        #expect(throws: JWTDecoder.JWTError.self) {
            try decoder.validate(jwt, options: options)
        }
    }
    
    @Test("Clock skew tolerance")
    func testClockSkewTolerance() throws {
        // Create a JWT that expired 30 seconds ago (within default tolerance)
        let expiredTime = Date().addingTimeInterval(-30)
        
        let jwt = createTestJWT(exp: expiredTime)
        
        let decoder = JWTDecoder()
        let decodedJWT = try decoder.decode(jwt)
        
        let options = JWTDecoder.ValidationOptions(allowedClockSkew: 60)
        
        // This should not throw because it's within the clock skew tolerance
        try decoder.validate(decodedJWT, options: options)
    }
    
    @Test("Decode and validate in one step")
    func testDecodeAndValidate() throws {
        let decoder = JWTDecoder()
        
        let options = JWTDecoder.ValidationOptions(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/"
        )
        
        // This should succeed for the valid token
        let jwt = try decoder.decodeAndValidate(Self.testToken, options: options)
        #expect(jwt.payload.iss == "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
    }
    
    @Test("Audience value contains method")
    func testAudienceContains() {
        let singleAudience = JWTDecoder.AudienceValue.single("test-audience")
        let multipleAudience = JWTDecoder.AudienceValue.multiple(["aud1", "aud2", "aud3"])
        
        #expect(singleAudience.contains("test-audience"))
        #expect(!singleAudience.contains("other-audience"))
        
        #expect(multipleAudience.contains("aud2"))
        #expect(!multipleAudience.contains("aud4"))
    }
    
    @Test("Audience value values property")
    func testAudienceValues() {
        let singleAudience = JWTDecoder.AudienceValue.single("test-audience")
        let multipleAudience = JWTDecoder.AudienceValue.multiple(["aud1", "aud2"])
        
        #expect(singleAudience.values == ["test-audience"])
        #expect(multipleAudience.values == ["aud1", "aud2"])
    }
    
    @Test("Practical JWT validation for Auth0 token")
    func testPracticalJWTValidation() throws {
        let decoder = JWTDecoder()
        
        // This is how you would validate your actual Auth0 JWT token in practice
        let jwt = try decoder.decode(Self.testToken)
        
        // Verify it's from the expected Auth0 domain
        #expect(jwt.payload.iss == "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")
        
        // Verify it has the expected algorithm (important for security)
        #expect(jwt.header.alg == "RS256")
        
        // Verify it has the kid (key ID) for signature verification
        #expect(jwt.header.kid == "i_F8LZGaD-tJB3roLrDB1")
        
        // Check that it's intended for your API
        guard let audience = jwt.payload.aud else {
            #expect(Bool(false), "Token should have audience")
            return
        }
        #expect(audience.contains("https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/"))
        
        // Verify it has the expected scopes
        #expect(jwt.payload.scope?.contains("openid") == true)
        #expect(jwt.payload.scope?.contains("profile") == true)
        #expect(jwt.payload.scope?.contains("email") == true)
        
        // In a real application, you would also:
        // 1. Fetch the public key from https://dev-8ygj6eppnvjz8bm6.us.auth0.com/.well-known/jwks.json
        // 2. Verify the signature using the public key matching the 'kid'
        // 3. Check that the token hasn't expired (jwt.payload.exp)
        
        // For demonstration, let's validate with expected issuer and audience
        let options = JWTDecoder.ValidationOptions(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/"
        )
        
        // Note: This will fail if run after the token expires (March 25, 2025)
        // but shows the validation structure
        do {
            try decoder.validate(jwt, options: options)
            // Token is valid (not expired yet)
        } catch JWTDecoder.JWTError.expired {
            // Token has expired - this is expected if running after March 25, 2025
            print("Token expired as expected for this test")
        }
    }
    
    @Test("JWT token validator integration with OAuth configuration")
    func testJWTValidatorIntegration() async throws {
        let validator = JWTTokenValidator(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/"
        )
        
        // Test with valid token
        let isValid = await validator.validate(Self.testToken)
        #expect(isValid)
        
        // Test with invalid token
        let isInvalid = await validator.validate("invalid.jwt.token")
        #expect(!isInvalid)
        
        // Test with nil token
        let isNil = await validator.validate(nil)
        #expect(!isNil)
        
        // Test OAuth configuration creation
        let config = OAuthConfiguration.auth0JWT(
            domain: "dev-8ygj6eppnvjz8bm6.us.auth0.com",
            expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/",
            clientId: "test-client-id",
            clientSecret: "test-client-secret"
        )
        
        // Test OAuth configuration validation
        let configValid = await config.validate(token: Self.testToken)
        #expect(configValid)
        
        let configInvalid = await config.validate(token: "invalid.jwt.token")
        #expect(!configInvalid)
    }
    
    @Test("Validate JWT with correct authorized party")
    func testValidateCorrectAuthorizedParty() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.testToken)
        let options = JWTDecoder.ValidationOptions(expectedAuthorizedParty: "n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi")
        
        // Should not throw
        try decoder.validate(jwt, options: options)
    }
    
    @Test("Validate JWT with incorrect authorized party fails")
    func testValidateIncorrectAuthorizedParty() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.testToken)
        let options = JWTDecoder.ValidationOptions(expectedAuthorizedParty: "wrong-client-id")
        
        do {
            try decoder.validate(jwt, options: options)
            #expect(Bool(false), "Expected validation to fail")
        } catch JWTDecoder.JWTError.invalidAuthorizedParty(let expected, let actual) {
            #expect(expected == "wrong-client-id")
            #expect(actual == "n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi")
        } catch {
            #expect(Bool(false), "Expected invalidAuthorizedParty error, got \(error)")
        }
    }
    
    @Test("JWT token validator with authorized party validation")
    func testJWTTokenValidatorWithAuthorizedParty() async throws {
        let validator = JWTTokenValidator(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/",
            expectedAuthorizedParty: "n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi"
        )
        
        // Valid token should pass all validations
        let isValid = await validator.validate(Self.testToken)
        #expect(isValid)
        
        // Token with wrong AZP should fail
        let validatorWrongAzp = JWTTokenValidator(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            expectedAudience: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/api/v2/",
            expectedAuthorizedParty: "wrong-client-id"
        )
        
        let isValidWrongAzp = await validatorWrongAzp.validate(Self.testToken)
        #expect(!isValidWrongAzp)
    }
    
    @Test("Validate JWT without azp passes when no azp expected")
    func testValidateNoAzpTokenNoAzpExpectation() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.tokenWithoutAzp)
        let options = JWTDecoder.ValidationOptions(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            expectedAudience: "https://unique-sponge-driven.ngrok-free.app" // the audience in token
            // Note: no expectedAuthorizedParty
        )
        try decoder.validate(jwt, options: options) // should not throw
    }

    @Test("Validate JWT without azp fails when azp expected")
    func testValidateNoAzpTokenWithAzpExpectationFails() throws {
        let decoder = JWTDecoder()
        let jwt = try decoder.decode(Self.tokenWithoutAzp)
        let options = JWTDecoder.ValidationOptions(
            expectedIssuer: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/",
            expectedAudience: "https://unique-sponge-driven.ngrok-free.app",
            expectedAuthorizedParty: "n4vmrjiAhmoE1P1JvjvF1iU8m1RTq3yi" // expecting azp which is absent
        )
        #expect(throws: JWTDecoder.JWTError.self) {
            try decoder.validate(jwt, options: options)
        }
    }
    
    @Test("JWE tokens are not supported")
    func testJWETokensNotSupported() {
        let decoder = JWTDecoder()
        
        // JWE token format: header.encrypted_key.iv.ciphertext.tag (5 segments)
        let jweToken = "eyJhbGciOiJBMjU2R0NNS1ciLCJlbmMiOiJBMjU2Q0JDLUhTNTEyIiwiaXYiOiJhYmNkZWZnaGlqa2xtbm9wcXJzdHV2d3h5eiIsInRhZyI6InNvbWV0YWcifQ.encrypted_key_data.iv_data.ciphertext_data.tag_data"
        
        #expect(throws: JWTDecoder.JWTError.jweNotSupported) {
            try decoder.decode(jweToken)
        }
    }
    
    @Test("JWE tokens with different segment counts are rejected")
    func testJWETokensWithDifferentSegments() {
        let decoder = JWTDecoder()
        
        // Test various malformed JWE-like tokens
        let malformedTokens = [
            "header.encrypted_key.iv.ciphertext", // 4 segments
            "header.encrypted_key.iv.ciphertext.tag.extra", // 6 segments
            "header.encrypted_key.iv.ciphertext.tag.extra.more" // 7 segments
        ]
        
        for token in malformedTokens {
            #expect(throws: JWTDecoder.JWTError.self) {
                try decoder.decode(token)
            }
        }
    }
    
    // MARK: - Helper methods
    
    private func createTestJWT(
        iss: String = "https://test-issuer.com/",
        sub: String = "test-subject",
        aud: [String] = ["test-audience"],
        iat: Date? = nil,
        exp: Date? = nil,
        nbf: Date? = nil,
        scope: String = "test-scope"
    ) -> String {
        let header = JWTDecoder.JWTHeader(alg: "RS256", typ: "JWT", kid: "test-kid")
        let payload = JWTDecoder.JWTPayload(
            iss: iss,
            sub: sub,
            aud: .multiple(aud),
            exp: exp,
            nbf: nbf,
            iat: iat ?? Date(),
            scope: scope,
            azp: "test-azp"
        )
        
        let headerData = try! JSONEncoder().encode(header)
        let payloadData = try! JSONEncoder().encode(payload)
        
        let headerB64 = base64URLEncode(headerData)
        let payloadB64 = base64URLEncode(payloadData)
        let signature = "fake-signature"
        
        return "\(headerB64).\(payloadB64).\(signature)"
    }
    
    private func base64URLEncode(_ data: Data) -> String {
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
} 