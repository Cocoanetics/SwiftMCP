import Foundation

extension JSONRPCMessage {
    /// Decode a single or batched JSON-RPC payload from `Data`.
    /// - Parameter data: Raw JSON data.
    /// - Returns: An array of `JSONRPCMessage` items.
    static func decodeMessages(from data: Data) throws -> [JSONRPCMessage] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let batch = try? decoder.decode([JSONRPCMessage].self, from: data) {
            return batch
        } else {
            let single = try decoder.decode(JSONRPCMessage.self, from: data)
            return [single]
        }
    }

    /// Whether `data` is a top-level JSON array (a JSON-RPC batch) rather than a
    /// single message.
    ///
    /// A single message is also decoded into a one-element array by
    /// ``decodeMessages(from:)-(Data)``, so inspecting the raw payload is the
    /// only reliable way to recover the wire shape afterwards.
    static func isBatchPayload(_ data: Data) -> Bool {
        for byte in data {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D:   // space, tab, LF, CR — skip leading JSON whitespace
                continue
            case UInt8(ascii: "["):
                return true
            default:
                return false
            }
        }
        return false   // empty or whitespace-only: not a batch
    }

    /// Whether a decoded payload must be rejected because it is a JSON-RPC batch
    /// and `version` removed batching support (`2025-06-18` onward).
    ///
    /// Revisions unknown to ``MCPProtocolVersion/profile(for:)`` — including any
    /// not-yet-negotiated version — are treated permissively, so the gate only
    /// fires when the version positively forbids batching.
    static func batchingRejected(body: Data, version: String) -> Bool {
        guard isBatchPayload(body), let profile = MCPProtocolVersion.profile(for: version) else {
            return false
        }
        return !profile.has(.jsonRPCBatching)
    }
}

#if Server
import NIOCore

extension JSONRPCMessage {
    /// Decode a single or batched JSON-RPC payload from a `ByteBuffer`.
    /// - Parameter buffer: Incoming buffer containing JSON data.
    static func decodeMessages(from buffer: ByteBuffer) throws -> [JSONRPCMessage] {
        var copy = buffer
        if let data = copy.readData(length: copy.readableBytes) {
            return try decodeMessages(from: data)
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let batch = try? decoder.decode([JSONRPCMessage].self, from: buffer) {
            return batch
        } else {
            let single = try decoder.decode(JSONRPCMessage.self, from: buffer)
            return [single]
        }
    }
}
#endif
