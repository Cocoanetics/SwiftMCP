#if Server
import SwiftCross
import Testing
import Crypto
import _CryptoExtras
@testable import SwiftMCP

@Suite("JWT Signature Verification", .tags(.unit))
struct JWTSignatureVerificationTests {

    static let issuer = "https://issuer.example.test/"
    static let kid = "test-key-1"

    // Token validity: iat 1751206127, exp one day later
    static let validDate = Date(timeIntervalSince1970: 1751206127)

    /// A freshly generated RSA key pair plus a cache seeded with its JWKS,
    /// so verification never touches the network.
    struct Fixture {
        let privateKey: _RSA.Signing.PrivateKey
        let cache: JWKSCache
        let issuerURL: URL

        init() async throws {
            privateKey = try _RSA.Signing.PrivateKey(keySize: .bits2048)
            let primitives = try privateKey.publicKey.getKeyPrimitives()
            let jwk = JSONWebKey(
                kty: "RSA",
                kid: JWTSignatureVerificationTests.kid,
                use: "sig",
                alg: "RS256",
                n: primitives.modulus.base64URLEncodedString(),
                e: primitives.publicExponent.base64URLEncodedString()
            )
            issuerURL = URL(string: JWTSignatureVerificationTests.issuer)!
            cache = JWKSCache()
            await cache.seed(JSONWebKeySet(keys: [jwk]), for: issuerURL)
        }

        /// Builds a compact JWS signed with the fixture's private key.
        func makeToken(typ: String, claims: String) throws -> String {
            let header = #"{"alg":"RS256","typ":"\#(typ)","kid":"\#(JWTSignatureVerificationTests.kid)"}"#
            let signingInput = Data(header.utf8).base64URLEncodedString()
                + "." + Data(claims.utf8).base64URLEncodedString()
            let signature = try privateKey.signature(for: Data(signingInput.utf8), padding: .insecurePKCS1v1_5)
            return signingInput + "." + signature.rawRepresentation.base64URLEncodedString()
        }

        func makeAccessToken() throws -> String {
            try makeToken(typ: "at+jwt", claims: """
            {"iss":"\(JWTSignatureVerificationTests.issuer)","sub":"user|1","aud":["https://api.example.test"],\
            "iat":1751206127,"exp":1751292527,"scope":"openid profile email"}
            """)
        }

        func makeIDToken() throws -> String {
            try makeToken(typ: "JWT", claims: """
            {"iss":"\(JWTSignatureVerificationTests.issuer)","aud":"client-id","sub":"user|1",\
            "email":"user@example.test","iat":1751206127,"exp":1751242127}
            """)
        }
    }

    @Test("Verify JWT signature using CryptoKit framework")
    func testJWTSignatureVerification() async throws {
        let fixture = try await Fixture()
        let jwt = try JSONWebToken(token: try fixture.makeAccessToken())

        let isValid = try await jwt.verify(using: fixture.issuerURL, at: Self.validDate, jwksCache: fixture.cache)

        #expect(isValid == true)
    }

    @Test("Verify ID token signature using CryptoKit framework")
    func testIDTokenSignatureVerification() async throws {
        let fixture = try await Fixture()
        let jwt = try JSONWebToken(token: try fixture.makeIDToken())

        let isValid = try await jwt.verify(using: fixture.issuerURL, at: Self.validDate, jwksCache: fixture.cache)

        #expect(isValid == true)
    }

    @Test("Reject modified JWT signature")
    func testRejectModifiedSignature() async throws {
        let fixture = try await Fixture()
        // Create a modified token with invalid signature
        let segments = try fixture.makeAccessToken().split(separator: ".")
        let modifiedToken = "\(segments[0]).\(segments[1]).invalid-signature"

        do {
            let jwt = try JSONWebToken(token: modifiedToken)
            _ = try await jwt.verify(using: fixture.issuerURL, at: Self.validDate, jwksCache: fixture.cache)
            #expect(Bool(false), "Expected verification to fail")
        } catch {
            #expect(error is JWTError)
        }
    }

    @Test("Reject JWT with unsupported algorithm")
    func testRejectUnsupportedAlgorithm() async throws {
        let fixture = try await Fixture()
        // Create a token with unsupported algorithm
        let header = #"{"alg":"HS256","typ":"JWT"}"#
        let payload = #"{"iss":"\#(Self.issuer)","sub":"test","exp":2524608000}"#
        let invalidToken = Data(header.utf8).base64URLEncodedString()
            + "." + Data(payload.utf8).base64URLEncodedString() + ".signature"

        do {
            let jwt = try JSONWebToken(token: invalidToken)
            _ = try await jwt.verify(using: fixture.issuerURL, jwksCache: fixture.cache)
            #expect(Bool(false), "Expected verification to fail")
        } catch let error as JWTError {
            #expect(error == .unsupportedAlgorithm)
        } catch {
            #expect(Bool(false), "Expected unsupportedAlgorithm error, got \(error)")
        }
    }

    @Test("JWKS caching works correctly")
    func testJWKSCaching() async throws {
        let fixture = try await Fixture()
        let jwks = try await fixture.cache.getJWKS(for: fixture.issuerURL)
        let jwt = try JSONWebToken(token: try fixture.makeAccessToken())

        let isValid = try jwt.verify(using: jwks, at: Self.validDate)

        #expect(isValid == true)
    }
}
#endif
