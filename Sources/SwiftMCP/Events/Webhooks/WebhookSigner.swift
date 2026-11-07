#if Server
//
//  WebhookSigner.swift
//  SwiftMCP
//
//  Standard Webhooks (https://www.standardwebhooks.com) signing and
//  verification for `events/*` webhook delivery: HMAC-SHA256 over
//  `"{id}.{timestamp}.{body}"`, `whsec_` + base64 secrets, `v1` signatures and
//  a replay window on the timestamp.
//

import Foundation
import Crypto

/// Why a webhook signature check failed.
public enum WebhookVerificationError: Error, Equatable, Sendable {
    case invalidSecret
    case missingHeader(String)
    case invalidTimestamp
    /// The timestamp is outside the replay window (too old or too far in the future).
    case timestampOutsideTolerance
    case noMatchingSignature
}

/// Signs and verifies Standard Webhooks deliveries.
public struct WebhookSigner: Sendable {
    public static let secretPrefix = "whsec_"
    /// Allowed size of the decoded secret, per the MCP Events profile.
    public static let secretByteRange = 24...64
    public static let idHeader = "webhook-id"
    public static let timestampHeader = "webhook-timestamp"
    public static let signatureHeader = "webhook-signature"
    public static let defaultTolerance: TimeInterval = 300

    private let key: SymmetricKey

    /// Creates a signer from a `whsec_`-prefixed base64 secret (the prefix is optional).
    public init(secret: String) throws {
        var encoded = secret
        if encoded.hasPrefix(Self.secretPrefix) {
            encoded.removeFirst(Self.secretPrefix.count)
        }
        guard let data = Data(base64Encoded: encoded), Self.secretByteRange.contains(data.count) else {
            throw WebhookVerificationError.invalidSecret
        }
        self.key = SymmetricKey(data: data)
    }

    /// Generates a fresh `whsec_` secret from 24 random bytes.
    public static func generateSecret() -> String {
        let bytes = (0..<24).map { _ in UInt8.random(in: .min ... .max) }
        return secretPrefix + Data(bytes).base64EncodedString()
    }

    /// Returns the `v1,<base64>` signature for a delivery.
    public func sign(id: String, timestamp: Int, body: Data) -> String {
        var message = Data("\(id).\(timestamp).".utf8)
        message.append(body)
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        return "v1," + Data(mac).base64EncodedString()
    }

    /// The three headers to attach to a delivery.
    public func headers(id: String, timestamp: Int, body: Data) -> [String: String] {
        [
            Self.idHeader: id,
            Self.timestampHeader: String(timestamp),
            Self.signatureHeader: sign(id: id, timestamp: timestamp, body: body)
        ]
    }

    /// Verifies a delivery. `signatureHeader` may hold several space-delimited
    /// signatures (key rotation); any matching `v1` signature is accepted.
    public func verify(
        id: String,
        timestamp: String,
        signatureHeader: String,
        body: Data,
        now: Date = Date(),
        tolerance: TimeInterval = WebhookSigner.defaultTolerance
    ) throws {
        guard let stamp = Int(timestamp) else {
            throw WebhookVerificationError.invalidTimestamp
        }
        if abs(now.timeIntervalSince1970 - TimeInterval(stamp)) > tolerance {
            throw WebhookVerificationError.timestampOutsideTolerance
        }

        let expected = Data(sign(id: id, timestamp: stamp, body: body).utf8)
        var matched = false
        for candidate in signatureHeader.split(separator: " ") {
            let candidateData = Data(candidate.utf8)
            if Self.constantTimeEquals(candidateData, expected) {
                matched = true
            }
        }
        guard matched else { throw WebhookVerificationError.noMatchingSignature }
    }

    /// Verifies a delivery from its HTTP headers (case-insensitive names).
    public func verify(
        headers: [String: String],
        body: Data,
        now: Date = Date(),
        tolerance: TimeInterval = WebhookSigner.defaultTolerance
    ) throws {
        let lowered = Dictionary(
            headers.map { ($0.key.lowercased(), $0.value) },
            uniquingKeysWith: { first, _ in first }
        )
        func value(_ name: String) throws -> String {
            guard let found = lowered[name] else { throw WebhookVerificationError.missingHeader(name) }
            return found
        }
        try verify(
            id: value(Self.idHeader),
            timestamp: value(Self.timestampHeader),
            signatureHeader: value(Self.signatureHeader),
            body: body,
            now: now,
            tolerance: tolerance
        )
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { diff |= left ^ right }
        return diff == 0
    }
}
#endif
