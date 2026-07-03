#if Server
//
//  MCPServer+RequestState.swift
//  SwiftMCP
//
//  The MRTR `requestState` machinery (MCP 2026-07-28, SEP-2322). `requestState`
//  round-trips through the client, so it is attacker-controlled input: the
//  payload is integrity-protected and carries the claims the spec asks servers
//  to verify — a short expiry, the authenticated principal, and a digest of the
//  originating request — plus the accumulated input responses that make
//  multi-round-trip re-execution stateless.
//

import Foundation
import Crypto

/// Signs and verifies the opaque MRTR `requestState` blob.
///
/// The default is ``HMACRequestStateSigner``; override
/// ``MCPServer/mrtrRequestStateSigner`` to supply a custom key (e.g. a shared
/// key across server instances) or an AEAD scheme.
public protocol MRTRRequestStateSigner: Sendable {
    /// Wraps `payload` into the opaque string handed to the client.
    func sign(_ payload: Data) -> String

    /// Unwraps a client-echoed state, returning the payload only if its
    /// integrity verifies. `nil` for tampered or malformed input.
    func verify(_ state: String) -> Data?
}

/// The default signer: HMAC-SHA256 with an ephemeral per-process key.
///
/// A restart invalidates in-flight states — harmless, because a client whose
/// retry fails verification simply receives a fresh ``InputRequiredResult`` and
/// starts the round trip over. Deployments running multiple instances behind a
/// balancer should supply a signer with a shared key instead.
public struct HMACRequestStateSigner: MRTRRequestStateSigner {
    private let key: SymmetricKey

    /// The process-wide default instance (ephemeral random key).
    public static let shared = HMACRequestStateSigner()

    public init(key: SymmetricKey = SymmetricKey(size: .bits256)) {
        self.key = key
    }

    public func sign(_ payload: Data) -> String {
        let mac = HMAC<SHA256>.authenticationCode(for: payload, using: key)
        return payload.base64URLEncodedString() + "." + Data(mac).base64URLEncodedString()
    }

    public func verify(_ state: String) -> Data? {
        let parts = state.split(separator: ".", maxSplits: 1)
        guard parts.count == 2,
              let payload = try? Data(base64URLEncoded: String(parts[0])),
              let mac = try? Data(base64URLEncoded: String(parts[1])) else {
            return nil
        }
        guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: payload, using: key) else {
            return nil
        }
        return payload
    }
}

/// The claims inside a `requestState` payload. `responses` is the accumulator
/// that makes multi-round-trip re-execution stateless: each round's state
/// carries every input response gathered so far, so the retried handler finds
/// answers for all earlier `elicit`/`sample` calls and only signals for new ones.
struct MRTRRequestStatePayload: Codable {
    /// Issued-at, seconds since 1970.
    var iat: Double
    /// Expiry, seconds since 1970 (issued-at + TTL).
    var exp: Double
    /// SHA-256 (base64url) of the bearer token, or `"anonymous"`.
    var principal: String
    /// SHA-256 (base64url) of the originating request's method + salient params.
    var requestDigest: String
    /// Accumulated input responses, keyed by ordinal id (`input-N`).
    var responses: [String: JSONValue]
}

public extension MCPServer {
    /// The signer protecting MRTR `requestState` blobs. Defaults to an
    /// HMAC-SHA256 signer with an ephemeral per-process key; override to bind a
    /// persistent or shared key, or an AEAD scheme.
    var mrtrRequestStateSigner: MRTRRequestStateSigner { HMACRequestStateSigner.shared }
}

// MARK: - Claims helpers

enum MRTRRequestState {
    /// How long a `requestState` stays valid. Bounds the replay window; the
    /// spec's SHOULD is "a short expiry".
    static let timeToLive: TimeInterval = 5 * 60

    /// The principal claim for the current request: a digest of the bearer
    /// token when one is present, else `"anonymous"`. Binding the principal
    /// rejects state replayed by a different caller.
    static func principal(accessToken: String?) -> String {
        guard let accessToken else {
            return "anonymous"
        }
        return Data(SHA256.hash(data: Data(accessToken.utf8))).base64URLEncodedString()
    }

    /// A digest identifying the originating request: the method plus the
    /// sorted-keys JSON of its salient params — with the MRTR bookkeeping fields
    /// (`inputResponses`, `requestState`) and `_meta` removed, so the digest is
    /// stable across retries of the same logical request.
    static func requestDigest(method: String, params: JSONValue?) -> String {
        var salient = params?.dictionaryValue ?? [:]
        salient.removeValue(forKey: "inputResponses")
        salient.removeValue(forKey: "requestState")
        salient.removeValue(forKey: "_meta")

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let paramsData = (try? encoder.encode(JSONValue.object(salient))) ?? Data()
        let digestInput = Data(method.utf8) + Data([0x0A]) + paramsData
        return Data(SHA256.hash(data: digestInput)).base64URLEncodedString()
    }
}

extension Data {
    /// base64url without padding — the JWT-style counterpart of
    /// `init(base64URLEncoded:)`.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
#endif
