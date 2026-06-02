#if Server
import Foundation
import NIO

actor SessionManager {
    struct BufferedEvent {
        let id: String
        let payload: Data
    }

    struct StreamRecord {
        let id: UUID
        let sessionID: UUID
        let kind: SSEStreamKind
        var continuation: AsyncStream<Data>.Continuation?
        var channel: Channel?
        var connectionToken: UUID?
        var nextSequence: Int = 1
        var buffer: [BufferedEvent] = []
        var isCompleted = false
        var lastActivityAt = Date()
        var lastConnectedAt: Date?
        var expiresAt: Date?

        var isActive: Bool {
            continuation != nil && (channel?.isActive ?? false)
        }
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

    internal var streams: [UUID: StreamRecord] = [:]
    internal var sessionStreams: [UUID: Set<UUID>] = [:]
    internal var primaryGeneralStreamIDs: [UUID: UUID] = [:]
    internal let eventBufferCapacity = 256

    init(
        transport: (any Transport)? = nil,
        retentionInterval: TimeInterval = 5 * 60
    ) {
        self.transport = transport
        self.retentionInterval = retentionInterval
    }

    /// Get all session IDs.
    var sessionIDs: [UUID] {
        Array(sessions.keys)
    }
}
#endif
