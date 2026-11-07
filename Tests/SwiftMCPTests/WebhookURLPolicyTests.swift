import Foundation
import Testing
@testable import SwiftMCP

@Suite("Webhook URL policy")
struct WebhookURLPolicyTests {
    let policy = WebhookURLPolicy()

    @Test func acceptsPublicHTTPS() throws {
        let result = try policy.validate("https://hooks.example.com/callback")
        #expect(result.host == "hooks.example.com")
        #expect(result.port == 443)
        _ = try policy.validate("https://8.8.8.8/x")
    }

    @Test func rejectsNonHTTPS() {
        #expect(throws: WebhookURLPolicyError.schemeNotAllowed("http")) {
            try policy.validate("http://example.com/")
        }
        #expect(throws: WebhookURLPolicyError.schemeNotAllowed("ftp")) {
            try policy.validate("ftp://example.com/")
        }
        #expect(throws: WebhookURLPolicyError.invalidURL) { try policy.validate("not a url") }
        #expect(throws: WebhookURLPolicyError.credentialsNotAllowed) {
            try policy.validate("https://u:p@example.com/")
        }
    }

    @Test(arguments: [
        "https://localhost/", "https://foo.localhost/",
        "https://127.0.0.1/", "https://127.1.2.3/", "https://10.0.0.1/",
        "https://172.16.0.1/", "https://172.31.255.255/", "https://192.168.1.1/",
        "https://169.254.169.254/", "https://100.64.0.1/", "https://0.0.0.0/",
        "https://[::1]/", "https://[::]/", "https://[fe80::1]/", "https://[fc00::1]/",
        "https://[fd12:3456::1]/", "https://[::ffff:127.0.0.1]/", "https://[::ffff:10.0.0.1]/",
        "https://[::ffff:a9fe:a9fe]/", "https://[64:ff9b::7f00:1]/", "https://[64:ff9b:1::7f00:1]/"
    ])
    func rejectsPrivateLoopbackLinkLocal(url: String) {
        #expect(throws: WebhookURLPolicyError.self) { try policy.validate(url) }
    }

    @Test func publicAddressesAreNotBlocked() {
        for address in ["8.8.8.8", "172.32.0.1", "172.15.0.1", "100.63.0.1", "2606:4700:4700::1111", "::ffff:8.8.8.8"] {
            #expect(!WebhookURLPolicy.isBlocked(address: address), "\(address)")
        }
        #expect(WebhookURLPolicy.isBlocked(address: "garbage"))
    }

    @Test func portAndHostAllowlists() throws {
        #expect(throws: WebhookURLPolicyError.portNotAllowed(8443)) { try policy.validate("https://example.com:8443/") }
        let custom = WebhookURLPolicy(allowedPorts: [443, 8443], allowedHosts: ["Hooks.Example.com"])
        _ = try custom.validate("https://hooks.example.com:8443/")
        #expect(throws: WebhookURLPolicyError.hostNotAllowed("other.example.com")) {
            try custom.validate("https://other.example.com/")
        }
    }

    @Test func dnsRebindingIsCaughtOnResolvedAddresses() async throws {
        let good = try await policy.validate("https://hooks.example.com/") { _ in ["93.184.216.34"] }
        #expect(good == ["93.184.216.34"])

        // One public and one private answer: reject the whole set.
        await #expect(throws: WebhookURLPolicyError.blockedAddress("10.0.0.5")) {
            try await policy.validate("https://evil.example.com/") { _ in ["93.184.216.34", "10.0.0.5"] }
        }
        await #expect(throws: WebhookURLPolicyError.resolutionFailed("empty.example.com")) {
            try await policy.validate("https://empty.example.com/") { _ in [] }
        }
    }
}
