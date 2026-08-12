#if Server
import Foundation
import Logging

actor SessionManager {
    /// The per-stream MCP metadata the generic ``SSEStreamHub`` does not track:
    /// which session a stream belongs to, and its MCP kind (general vs request).
    struct StreamMeta {
        let sessionID: UUID
        let kind: SSEStreamKind
        /// When the stream last started waiting for a live connection to bind —
        /// stamped at open and refreshed on resume. The hub only starts its
        /// retention clock on disconnect/finish, so a stream whose connection
        /// never binds has no expiry at all; `cleanupExpiredState` reclaims it
        /// once this is a full retention interval in the past.
        let attachGraceStart: Date

        init(sessionID: UUID, kind: SSEStreamKind, attachGraceStart: Date = Date()) {
            self.sessionID = sessionID
            self.kind = kind
            self.attachGraceStart = attachGraceStart
        }
    }

    enum StreamResumeError: Error {
        case malformedEventID
        case unknownStream
        case sessionMismatch
        case resumePointUnavailable
    }

    internal let logger = Logger(label: "com.cocoanetics.SwiftMCP.SessionManager")

    internal var sessions: [UUID: Session] = [:]
    internal weak var transport: (any Transport)?
    internal let retentionInterval: TimeInterval

    /// Sessions whose most recent resource-updated broadcast could not be
    /// routed, so the outage is logged once instead of once per broadcast.
    internal var sessionsWithUndeliverableBroadcast: Set<UUID> = []

    /// Total resource-updated notifications dropped because a subscribed
    /// session had no routable general stream. Diagnostic counter.
    internal var undeliverableBroadcastCount = 0

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
