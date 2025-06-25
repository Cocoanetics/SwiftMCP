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
            #expect(true)
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
            #expect(true)
        } else {
            #expect(Bool(false), "Expected unauthorized result")
        }
    }
}
