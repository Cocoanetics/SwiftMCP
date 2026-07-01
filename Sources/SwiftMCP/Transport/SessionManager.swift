#if Server
import Foundation

actor SessionManager {
    /// The per-stream MCP metadata the generic ``SSEStreamHub`` does not track:
    /// which session a stream belongs to, and its MCP kind (general vs request).
    struct StreamMeta {
        let sessionID: UUID
        let kind: SSEStreamKind
    }

    enum StreamResumeError: Error {
        case malformedEventID
        case unknownStream
        case sessionMismatch
        case resumePointUnavailable
    }

    internal var sessions: [UUID: Session] = [:]
    internal weak var transport: (any Transport)?
    internal let retentionInterval: TimeInterval

    /// The transport-agnostic SSE registry — replay buffer, resume-after-disconnect,
    /// and retention — shared with LSP/ACP via JSONFoundation. It is *synchronous*
    /// and lives inside this actor, so a compound operation that reads
    /// ``SSEStreamHub/info(streamID:)`` and then mutates never interleaves with
    /// another. SessionManager layers MCP policy (sessions, stream kinds, the
    /// primary general stream) on top via ``streamMeta``.
    internal let hub: SSEStreamHub
    internal var streamMeta: [UUID: StreamMeta] = [:]
    internal var sessionStreams: [UUID: Set<UUID>] = [:]
    internal var primaryGeneralStreamIDs: [UUID: UUID] = [:]

    init(
        transport: (any Transport)? = nil,
        retentionInterval: TimeInterval = 5 * 60
    ) {
        self.transport = transport
        self.retentionInterval = retentionInterval
        self.hub = SSEStreamHub(bufferCapacity: 256, retentionInterval: retentionInterval)
    }

    /// Get all session IDs.
    var sessionIDs: [UUID] {
        Array(sessions.keys)
    }
}

/// Bridges the SwiftMCP ``SSEConnection`` seam (a transport adapter's live
/// connection) to JSONFoundation's ``SSEStreamSink`` (what the hub uses to test
/// liveness and force a connection closed).
struct SSEConnectionSink: SSEStreamSink {
    let connection: any SSEConnection
    var isLive: Bool { connection.isConnected }
    func close() { connection.terminate() }
}
#endif
