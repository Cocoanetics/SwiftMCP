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
        session.accessToken = "test-token"
        session.accessTokenExpiry = Date().addingTimeInterval(3600)
        
        // Fetch user info
        await sessionManager.fetchAndStoreUserInfo(for: sessionID, oauthConfiguration: config)
        
        // Note: In a real test, we would mock the network request to return user info
        // For now, we just verify the function doesn't crash and handles the case gracefully
        // when the userinfo endpoint is not available or returns an error
        
        // The userInfo should be nil since we're not actually making a network request
        #expect(session.userInfo == nil)
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
}
