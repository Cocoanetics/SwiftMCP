#if Server
import Foundation
import Testing
@testable import SwiftMCP

@Suite("OAuth Conformance", .tags(.unit))
struct OAuthConformanceTests {
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

    @Test("Duplicate iss parameter is rejected (RFC 9207)")
    func duplicateIssuerRejected() {
        #expect(throws: OAuthConformanceError.duplicateIssuer) {
            try OAuthAuthorizationResponse.validateIssuer(
                redirectURL: URL(string: "https://app/cb?iss=https%3A%2F%2Fa.example&iss=https%3A%2F%2Fb.example")!,
                expectedIssuer: "https://a.example",
                issuerParameterSupported: true)
        }
    }

    @Test("CIMD rejects credentials, dot segments, secrets and bad redirect URIs")
    func clientIDMetadataDocumentStrictness() {
        let bads = [
            "https://user:pw@app.example/c.json",
            "https://app.example/a/../c.json",
            "https://app.example/./c.json"
        ]
        for bad in bads {
            #expect(throws: OAuthConformanceError.self) { _ = try ClientIDMetadataDocument.validateClientID(bad) }
        }
        let id = "https://app.example/client.json"
        let base = #""client_id":"https://app.example/client.json","client_name":"App""#
        for extra in [
            #","redirect_uris":["http://127.0.0.1/cb"],"client_secret":"s""#,
            #","redirect_uris":["http://127.0.0.1/cb"],"token_endpoint_auth_method":"client_secret_basic""#,
            #","redirect_uris":["not a url"]"#
        ] {
            #expect(throws: OAuthConformanceError.self) {
                try ClientIDMetadataDocument.validate(document: Data("{\(base)\(extra)}".utf8), fetchedFrom: id)
            }
        }
    }

    @Test("Proxy rejects registration without application_type")
    func proxyRejectsRegistrationWithoutApplicationType() async throws {
        let transport = HTTPSSETransport(server: Calculator())
        transport.oauthConfiguration = OAuthConfiguration(
            issuer: URL(string: "https://example.com")!,
            authorizationEndpoint: URL(string: "https://example.com/authorize")!,
            tokenEndpoint: URL(string: "https://example.com/token")!,
            registrationEndpoint: URL(string: "https://example.com/register")!,
            transparentProxy: true)
        let request = HTTPRouteRequest<Data?>(
            method: .post, uri: "/oauth/register", path: "/oauth/register", headerFields: [:],
            body: Data(#"{"client_name":"x"}"#.utf8), pathParams: [:], queryParams: [])
        let response = try await transport.handleOAuthProxy(request: request)
        #expect(response.status.code == 400)
        let body = try JSONSerialization.jsonObject(with: response.body ?? Data()) as? [String: String]
        #expect(body?["error"] == "invalid_client_metadata")
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
