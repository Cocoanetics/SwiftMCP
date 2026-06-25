import Foundation

extension JSONRPCMessage {
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

    /// Whether a decoded frame must be rejected because it is a JSON-RPC batch
    /// and `version` removed batching support (`2025-06-18` onward).
    ///
    /// The byte-level ``batchingRejected(body:version:)`` is unavailable once a
    /// connection has decoded the wire payload, so this works off the frame: a
    /// frame carrying more than one message is unambiguously a batch.
    static func batchingRejected(frame: [JSONRPCMessage], version: String) -> Bool {
        guard frame.count > 1, let profile = MCPProtocolVersion.profile(for: version) else {
            return false
        }
        return !profile.has(.jsonRPCBatching)
    }

    /// The protocol version that governs batching on a session-bound transport
    /// (stdio, TCP, in-process): the session's negotiated version, else a
    /// leading `initialize`'s declared version, else `latest` — mirroring the
    /// HTTP resolution order.
    static func batchingVersion(for messages: [JSONRPCMessage], session: Session) async -> String {
        await session.negotiatedProtocolVersion
            ?? SessionInitializationGate.initializeProtocolVersion(messages)
            ?? MCPProtocolVersion.latest
    }

    /// The JSON-RPC error response for a batch rejected under `version`.
    static func batchingRejectionResponse(version: String) -> JSONRPCMessage {
        .errorResponse(
            id: nil,
            error: .init(
                code: -32600,
                message: "JSON-RPC batching is not supported in protocol version \(version)."
            )
        )
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
