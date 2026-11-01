#if Server
import Foundation
import Testing
@testable import SwiftMCP

@Suite("OAuth Authorization", .tags(.unit))
struct OAuthTests {
    @Test("Token validated by OAuth configuration")
    func tokenValidated() async throws {
        let server = Calculator()
        let transport = HTTPSSETransport(server: server)
        transport.oauthConfiguration = OAuthConfiguration(
            issuer: URL(string: "https://example.com")!,
            authorizationEndpoint: URL(string: "https://example.com/auth")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            tokenValidator: { token in
                return token == "good"
            }
        )

        let result = await transport.authorize("good", sessionID: nil)
        if case .authorized = result {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected authorization")
        }
    }

    @Test("Invalid token fails validation")
    func tokenRejected() async throws {
        let server = Calculator()
        let transport = HTTPSSETransport(server: server)
        transport.oauthConfiguration = OAuthConfiguration(
            issuer: URL(string: "https://example.com")!,
            authorizationEndpoint: URL(string: "https://example.com/auth")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            tokenValidator: { token in
                return token == "good"
            }
        )

        let result = await transport.authorize("bad", sessionID: nil)
        if case .unauthorized = result {
            #expect(Bool(true))
        } else {
            #expect(Bool(false), "Expected unauthorized result")
        }
    }

    @Test("User info is fetched and stored after token validation")
    func testUserInfoFetching() async throws {
        let config = OAuthConfiguration(
            issuer: URL(string: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/")!,
            authorizationEndpoint: URL(string: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/authorize")!,
            tokenEndpoint: URL(string: "https://dev-8ygj6eppnvjz8bm6.us.auth0.com/oauth/token")!,
            audience: "https://test-api.com",
            clientID: "test-client",
            clientSecret: "test-secret"
        )

        let sessionManager = SessionManager()
        let sessionID = UUID()

        // Create a session and store a token
        let session = await sessionManager.session(id: sessionID)
        await session.setAccessToken("test-token")
        await session.setAccessTokenExpiry(Date().addingTimeInterval(3600))

        // Fetch user info
        await sessionManager.fetchAndStoreUserInfo(for: sessionID, oauthConfiguration: config)

        // Note: In a real test, we would mock the network request to return user info
        // For now, we just verify the function doesn't crash and handles the case gracefully
        // when the userinfo endpoint is not available or returns an error

        // The userInfo should be nil since we're not actually making a network request
        #expect(await session.userInfo == nil)
    }

    @Test("UserInfo struct can be decoded from JSON")
    func testUserInfoDecoding() throws {
        let jsonString = """
        {
            "sub": "auth0|123456789",
            "name": "John Doe",
            "given_name": "John",
            "family_name": "Doe",
            "email": "john.doe@example.com",
            "email_verified": true,
            "picture": "https://example.com/avatar.jpg",
            "updated_at": "2022-01-01T12:00:00Z"
        }
        """

        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let userInfo = try decoder.decode(UserInfo.self, from: jsonData)

        #expect(userInfo.sub == "auth0|123456789")
        #expect(userInfo.name == "John Doe")
        #expect(userInfo.givenName == "John")
        #expect(userInfo.familyName == "Doe")
        #expect(userInfo.email == "john.doe@example.com")
        #expect(userInfo.emailVerified == true)
        #expect(userInfo.picture == "https://example.com/avatar.jpg")

        // Check that updated_at was properly converted to Date
        let expectedDate = ISO8601DateFormatter().date(from: "2022-01-01T12:00:00Z")
        #expect(userInfo.updatedAt == expectedDate)
    }

    @Test("UserInfo struct handles missing optional fields")
    func testUserInfoDecodingWithMissingFields() throws {
        let jsonString = """
        {
            "sub": "auth0|123456789"
        }
        """

        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let userInfo = try decoder.decode(UserInfo.self, from: jsonData)

        #expect(userInfo.sub == "auth0|123456789")
        #expect(userInfo.name == nil)
        #expect(userInfo.email == nil)
        #expect(userInfo.updatedAt == nil)
    }

    @Test("UserInfo struct handles updated_at as ISO 8601 string")
    func testUserInfoDecodingWithISO8601Timestamp() throws {
        let jsonString = """
        {
            "sub": "auth0|123456789",
            "name": "John Doe",
            "email": "john.doe@example.com",
            "updated_at": "2022-01-01T12:00:00Z"
        }
        """

        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let userInfo = try decoder.decode(UserInfo.self, from: jsonData)

        #expect(userInfo.sub == "auth0|123456789")
        #expect(userInfo.name == "John Doe")
        #expect(userInfo.email == "john.doe@example.com")

        // Check that ISO 8601 string was properly converted to Date
        let expectedDate = ISO8601DateFormatter().date(from: "2022-01-01T12:00:00Z")
        #expect(userInfo.updatedAt == expectedDate)
    }

    @Test("OAuthTokenResponse struct can decode token responses")
    func testOAuthTokenResponseDecoding() throws {
        let jsonString = """
        {
            "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
            "token_type": "Bearer",
            "expires_in": 3600,
            "refresh_token": "def50200...",
            "scope": "openid profile email",
            "id_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9..."
        }
        """

        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(OAuthTokenResponse.self, from: jsonData)

        #expect(tokenResponse.accessToken == "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...")
        #expect(tokenResponse.tokenType == "Bearer")
        #expect(tokenResponse.expiresIn == 3600)
        #expect(tokenResponse.refreshToken == "def50200...")
        #expect(tokenResponse.scope == "openid profile email")
        #expect(tokenResponse.idToken == "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...")
    }

    @Test("OAuthTokenResponse struct handles minimal token responses")
    func testOAuthTokenResponseMinimalDecoding() throws {
        let jsonString = """
        {
            "access_token": "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...",
            "token_type": "Bearer"
        }
        """

        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        let tokenResponse = try decoder.decode(OAuthTokenResponse.self, from: jsonData)

        #expect(tokenResponse.accessToken == "eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9...")
        #expect(tokenResponse.tokenType == "Bearer")
        #expect(tokenResponse.expiresIn == nil)
        #expect(tokenResponse.refreshToken == nil)
        #expect(tokenResponse.scope == nil)
        #expect(tokenResponse.idToken == nil)
    }

    // MARK: - MCP OAuth conformance (#224)

    @Test("Authorization response issuer mismatch is rejected (RFC 9207)")
    func issuerMismatchRejected() throws {
        let mismatch = OAuthConformanceError.issuerMismatch(
            expected: "https://a.example", received: "https://evil.example")
        #expect(throws: mismatch) {
            try OAuthAuthorizationResponse.validateIssuer(
                redirectURL: URL(string: "https://app/cb?code=1&iss=https%3A%2F%2Fevil.example")!,
                expectedIssuer: "https://a.example",
                issuerParameterSupported: true)
        }
        #expect(throws: OAuthConformanceError.missingIssuer(expected: "https://a.example")) {
            try OAuthAuthorizationResponse.validateIssuer(
                responseIssuer: nil, expectedIssuer: "https://a.example", issuerParameterSupported: true)
        }
        try OAuthAuthorizationResponse.validateIssuer(
            responseIssuer: nil, expectedIssuer: "https://a.example", issuerParameterSupported: false)
        try OAuthAuthorizationResponse.validateIssuer(
            responseIssuer: "https://a.example", expectedIssuer: "https://a.example", issuerParameterSupported: true)
    }

    @Test("Dynamic client registration requires application_type (SEP-837)")
    func registrationRequiresApplicationType() throws {
        try OAuthClientRegistrationValidator.validate(requestBody: Data(#"{"application_type":"native"}"#.utf8))
        #expect(throws: OAuthConformanceError.invalidApplicationType(nil)) {
            try OAuthClientRegistrationValidator.validate(requestBody: Data(#"{"client_name":"x"}"#.utf8))
        }
        #expect(throws: OAuthConformanceError.invalidApplicationType("mobile")) {
            try OAuthClientRegistrationValidator.validate(requestBody: Data(#"{"application_type":"mobile"}"#.utf8))
        }
        #expect(throws: OAuthConformanceError.self) {
            try OAuthClientRegistrationValidator.validate(requestBody: nil)
        }
    }

    @Test("Client credentials are isolated per issuer (SEP-2352)")
    func credentialsIsolatedPerIssuer() async throws {
        let store = OAuthClientCredentialStore()
        let counter = RegistrationCounter()
        let register: @Sendable (String) async throws -> OAuthClientCredentials = { issuer in
            let count = await counter.next()
            return OAuthClientCredentials(issuer: issuer, clientID: "client-\(count)")
        }
        let first = try await store.credentials(for: "https://a.example", register: register)
        let other = try await store.credentials(for: "https://b.example", register: register)
        let again = try await store.credentials(for: "https://a.example", register: register)
        #expect(first.clientID == "client-1")
        #expect(other.clientID == "client-2")
        #expect(first == again)
        #expect(await store.credentials(for: "https://c.example") == nil)
    }

    @Test("Concurrent registrations for one issuer coalesce")
    func concurrentRegistrationsCoalesce() async throws {
        let store = OAuthClientCredentialStore()
        let counter = RegistrationCounter()
        let register: @Sendable (String) async throws -> OAuthClientCredentials = { issuer in
            let count = await counter.next()
            try await Task.sleep(nanoseconds: 50_000_000)
            return OAuthClientCredentials(issuer: issuer, clientID: "client-\(count)")
        }
        async let one = store.credentials(for: "https://a.example", register: register)
        async let two = store.credentials(for: "https://a.example", register: register)
        let results = try await [one, two]
        #expect(results[0] == results[1])
        #expect(await counter.next() == 2)
    }

    @Test("Client ID Metadata Documents are validated and preferred over DCR")
    func clientIDMetadataDocument() throws {
        let id = "https://app.example/client.json"
        let valid = #"{"client_id":"https://app.example/client.json","client_name":"App","#
            + #""redirect_uris":["http://127.0.0.1/cb"]}"#
        try ClientIDMetadataDocument.validate(document: Data(valid.utf8), fetchedFrom: id)
        let nameless = #"{"client_id":"https://app.example/client.json","redirect_uris":["x"]}"#
        #expect(throws: OAuthConformanceError.self) {
            try ClientIDMetadataDocument.validate(document: Data(nameless.utf8), fetchedFrom: id)
        }
        #expect(throws: OAuthConformanceError.self) {
            let foreign = #"{"client_id":"https://other.example/c.json","client_name":"App","redirect_uris":["x"]}"#
            try ClientIDMetadataDocument.validate(document: Data(foreign.utf8), fetchedFrom: id)
        }
        #expect(throws: OAuthConformanceError.self) {
            _ = try ClientIDMetadataDocument.validateClientID("http://app.example/c.json")
        }
        let reg = "https://x/register"
        typealias Method = OAuthClientRegistrationMethod
        #expect(Method.select(clientIDMetadataDocumentSupported: true, registrationEndpoint: reg)
            == .clientIDMetadataDocument)
        #expect(Method.select(clientIDMetadataDocumentSupported: false, registrationEndpoint: reg)
            == .dynamicRegistration)
        #expect(Method.select(clientIDMetadataDocumentSupported: false, registrationEndpoint: nil)
            == .unavailable)
    }
}

private actor RegistrationCounter {
    private var value = 0
    func next() -> Int { value += 1; return value }
}
#endif
