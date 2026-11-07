#if Server
//
//  WebhookCallbackVerification.swift
//  SwiftMCP
//
//  Callback verification handshake: before activating a webhook subscription
//  the server POSTs a signed challenge to the callback URL; the receiver proves
//  it controls the endpoint by answering 2xx and echoing the challenge.
//

import Foundation

/// Pure logic for the webhook callback verification handshake.
public enum WebhookCallbackVerification {
    /// `type` of the challenge body.
    public static let challengeType = "verification"

    /// Body POSTed to the callback URL.
    public struct Challenge: Codable, Sendable, Equatable {
        public let type: String
        public let challenge: String

        public init(challenge: String = Challenge.generateToken()) {
            self.type = WebhookCallbackVerification.challengeType
            self.challenge = challenge
        }

        /// A random URL-safe token (32 bytes of entropy).
        public static func generateToken() -> String {
            let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
            return Data(bytes).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        public func body() throws -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(self)
        }
    }

    /// Returns `true` if the receiver's response proves control of the callback:
    /// a 2xx status whose body is the challenge as plain text, or a JSON object
    /// with a `challenge` string field equal to it.
    public static func isValidResponse(statusCode: Int, body: Data, for challenge: Challenge) -> Bool {
        guard (200..<300).contains(statusCode) else { return false }

        var echoed: String?
        if let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            echoed = object["challenge"] as? String
        } else {
            echoed = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let echoed else { return false }
        return constantTimeEquals(Data(echoed.utf8), Data(challenge.challenge.utf8))
    }

    private static func constantTimeEquals(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var diff: UInt8 = 0
        for (left, right) in zip(lhs, rhs) { diff |= left ^ right }
        return diff == 0
    }
}
#endif
