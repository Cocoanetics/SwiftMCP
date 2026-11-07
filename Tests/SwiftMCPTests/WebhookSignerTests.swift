#if Server
import Foundation
import Testing
@testable import SwiftMCP

@Suite("Webhook signer")
struct WebhookSignerTests {
    // Standard Webhooks reference vector.
    static let secret = "whsec_MfKQ9r8GKYqrTwjUPD8ILPZIo2LaLaSw"
    static let id = "msg_p5jXN8AQM9LWM0D4loKWxJek"
    static let timestamp = 1614265330
    static let body = Data(#"{"test": 2432232314}"#.utf8)
    static let signature = "v1,g0hM9SsE+OTPJTGt/tmIKtSyZlE3uFJELVlNIOLJ1OE="
    static let tampered = Data(#"{"test": 2432232315}"#.utf8)
    static let now = Date(timeIntervalSince1970: TimeInterval(timestamp + 10))

    static func check(
        _ signer: WebhookSigner,
        timestamp: String = String(timestamp),
        signature: String = signature,
        body: Data = body,
        now: Date = now
    ) throws {
        try signer.verify(id: id, timestamp: timestamp, signatureHeader: signature, body: body, now: now)
    }

    @Test func signMatchesReferenceVector() throws {
        let signer = try WebhookSigner(secret: Self.secret)
        #expect(signer.sign(id: Self.id, timestamp: Self.timestamp, body: Self.body) == Self.signature)
    }

    @Test func verifyAcceptsReferenceVector() throws {
        let signer = try WebhookSigner(secret: Self.secret)
        try Self.check(signer, signature: Self.signature, body: Self.body, now: Self.now)
    }

    @Test func verifyAcceptsRotatedSignatureList() throws {
        let signer = try WebhookSigner(secret: Self.secret)
        try Self.check(signer, signature: "v1,AAAA \(Self.signature)", body: Self.body, now: Self.now)
    }

    @Test func verifyFromHeadersIsCaseInsensitive() throws {
        let signer = try WebhookSigner(secret: Self.secret)
        let headers = [
            "Webhook-Id": Self.id,
            "Webhook-Timestamp": String(Self.timestamp),
            "Webhook-Signature": Self.signature
        ]
        try signer.verify(headers: headers, body: Self.body, now: Self.now)
        #expect(throws: WebhookVerificationError.missingHeader("webhook-id")) {
            try signer.verify(headers: [:], body: Self.body, now: Self.now)
        }
    }

    @Test func rejectsStaleAndFutureTimestamps() throws {
        let signer = try WebhookSigner(secret: Self.secret)
        for offset in [301.0, -301.0] {
            let checkTime = Date(timeIntervalSince1970: TimeInterval(Self.timestamp) + offset)
            #expect(throws: WebhookVerificationError.timestampOutsideTolerance) {
                try Self.check(signer, signature: Self.signature, body: Self.body, now: checkTime)
            }
        }
    }

    @Test func rejectsTamperedBody() throws {
        let signer = try WebhookSigner(secret: Self.secret)
        #expect(throws: WebhookVerificationError.noMatchingSignature) {
            try Self.check(signer, signature: Self.signature, body: Self.tampered, now: Self.now)
        }
    }

    @Test func rejectsWrongSecretAndBadInput() throws {
        let other = try WebhookSigner(secret: WebhookSigner.generateSecret())
        #expect(throws: WebhookVerificationError.noMatchingSignature) {
            try Self.check(other, signature: Self.signature, body: Self.body, now: Self.now)
        }
        #expect(throws: WebhookVerificationError.invalidTimestamp) {
            try Self.check(other, timestamp: "abc", signature: Self.signature, body: Self.body, now: Self.now)
        }
        #expect(throws: WebhookVerificationError.invalidSecret) { try WebhookSigner(secret: "whsec_!!!") }
        #expect(throws: WebhookVerificationError.invalidSecret) { try WebhookSigner(secret: "whsec_YQ==") }
        let long = "whsec_" + Data(repeating: 1, count: 65).base64EncodedString()
        #expect(throws: WebhookVerificationError.invalidSecret) { try WebhookSigner(secret: long) }
    }

    @Test func callbackChallengeHandshake() throws {
        let challenge = WebhookCallbackVerification.Challenge()
        let body = try challenge.body()
        #expect(String(data: body, encoding: .utf8)?.contains("\"verification\"") == true)
        let plain = Data(challenge.challenge.utf8)
        let json = Data(#"{"challenge":"\#(challenge.challenge)"}"#.utf8)
        typealias Handshake = WebhookCallbackVerification
        #expect(Handshake.isValidResponse(statusCode: 200, body: plain, for: challenge))
        #expect(Handshake.isValidResponse(statusCode: 204, body: json, for: challenge))
        #expect(!Handshake.isValidResponse(statusCode: 500, body: plain, for: challenge))
        #expect(!Handshake.isValidResponse(statusCode: 200, body: Data("nope".utf8), for: challenge))
        #expect(!Handshake.isValidResponse(statusCode: 200, body: Data(), for: challenge))
    }
}
#endif
