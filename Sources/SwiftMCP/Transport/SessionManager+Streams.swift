#if Server
import Foundation

extension SessionManager {
    /// Returns the current number of bound SSE connections.
    var channelCount: Int {
        get async {
            await cleanupExpiredState()
            return hub.attachedStreamIDs().count
        }
    }

    /// Create a new SSE stream for the given session and return the AsyncStream to write to the response.
    ///
    /// `resumable: false` (the modern era's per-request streams) opens the hub
    /// stream without a replay buffer or priming anchor: no `id:` fields reach the
    /// wire and nothing is retained for a `Last-Event-ID` resume — modern streams
    /// must not advertise or support resumability.
    func createStream(
        sessionID: UUID,
        kind: SSEStreamKind,
        resumable: Bool = true
    ) async -> (AsyncStream<Data>, StreamRouteResponseInfo) {
        await cleanupExpiredState()
        let session = await session(id: sessionID)
        await session.touchActivity()

        // The hub assigns the stream id, buffers replayable data events, and emits
        // the priming event for replayable streams. MCP kind maps to its flags:
        // legacy general streams are fire-and-forget; request streams stop
        // accepting once finished; general streams keep accepting.
        let (stream, streamID) = hub.open(
            replayable: resumable && kind != .legacyGeneral,
            primed: resumable && kind != .legacyGeneral,
            rejectsSendAfterCompletion: kind == .request
        )
        streamMeta[streamID] = StreamMeta(sessionID: sessionID, kind: kind)
        sessionStreams[sessionID, default: []].insert(streamID)

        if kind.isGeneral {
            primaryGeneralStreamIDs[sessionID] = streamID
        }

        return (stream, StreamRouteResponseInfo(sessionID: sessionID, streamID: streamID))
    }

    /// Resume an existing retained stream from the specified Last-Event-ID.
    func resumeStream(
        sessionID: UUID,
        after lastEventID: String
    ) async throws -> (AsyncStream<Data>, StreamRouteResponseInfo) {
        await cleanupExpiredState()

        guard let eventID = SSEEventID(lastEventID) else {
            throw StreamResumeError.malformedEventID
        }
        guard let meta = streamMeta[eventID.streamID] else {
            throw StreamResumeError.unknownStream
        }
        guard meta.sessionID == sessionID else {
            throw StreamResumeError.sessionMismatch
        }

        let stream: AsyncStream<Data>
        do {
            stream = try hub.resume(streamID: eventID.streamID, after: eventID)
        } catch SSEStreamResumeError.unknownStream {
            throw StreamResumeError.unknownStream
        } catch SSEStreamResumeError.resumePointUnavailable {
            throw StreamResumeError.resumePointUnavailable
        }

        if let session = sessions[sessionID] {
            await session.touchActivity()
        }

        // The hub finishes + retains a stream that was already completed; mirror
        // the session-side reconciliation the original did via markStreamDisconnected.
        if let info = hub.info(streamID: eventID.streamID), info.isCompleted {
            if meta.kind.isGeneral {
                selectPrimaryGeneralStream(for: sessionID, keepRetainedCurrent: true)
            }
            await updateSessionExpiry(for: sessionID)
        }

        return (stream, StreamRouteResponseInfo(sessionID: sessionID, streamID: eventID.streamID))
    }

    /// Register a live connection for a specific stream.
    func register(connection: any SSEConnection, sessionID: UUID, streamID: UUID) async -> UUID? {
        await cleanupExpiredState()
        guard let meta = streamMeta[streamID], meta.sessionID == sessionID else {
            return nil
        }

        let sink = SSEConnectionSink(connection: connection)
        guard let connectionToken = hub.attach(sink: sink, streamID: streamID) else {
            return nil
        }

        if meta.kind.isGeneral {
            primaryGeneralStreamIDs[sessionID] = streamID
        }

        if let session = sessions[sessionID] {
            await session.touchActivity()
        }

        return connectionToken
    }

    /// Mark a stream's current connection as closed while retaining its buffer for resume.
    func markStreamDisconnected(streamID: UUID, connectionToken: UUID?) async {
        await cleanupExpiredState()
        guard let meta = streamMeta[streamID] else {
            return
        }
        // The hub applies the connection-token dedup guard; a stale signal is a no-op.
        guard hub.markDisconnected(streamID: streamID, connectionToken: connectionToken) else {
            return
        }

        if meta.kind.isGeneral {
            selectPrimaryGeneralStream(for: meta.sessionID, keepRetainedCurrent: true)
        }

        await updateSessionExpiry(for: meta.sessionID)
    }

    /// Finish a stream after the server has emitted its terminal response.
    func finishStream(streamID: UUID) async {
        await cleanupExpiredState()
        guard let meta = streamMeta[streamID] else {
            return
        }

        hub.finish(streamID: streamID)

        if meta.kind.isGeneral {
            selectPrimaryGeneralStream(for: meta.sessionID, keepRetainedCurrent: true)
        }

        await updateSessionExpiry(for: meta.sessionID)
    }

    /// Return all active stream identifiers.
    func activeStreamIDs() async -> [UUID] {
        await cleanupExpiredState()
        return hub.activeStreamIDs()
    }

    /// Check if any stream for a session is currently active.
    func hasActiveConnection(for sessionID: UUID) async -> Bool {
        await cleanupExpiredState()
        guard let streamIDs = sessionStreams[sessionID] else {
            return false
        }
        return streamIDs.contains { hub.isActive(streamID: $0) }
    }

    /// Check whether the primary general stream is currently active.
    func hasActivePrimaryGeneralConnection(for sessionID: UUID) async -> Bool {
        await cleanupExpiredState()
        guard let streamID = primaryGeneralStreamIDs[sessionID] else {
            return false
        }
        return hub.isActive(streamID: streamID)
    }

    func primaryGeneralStreamID(for sessionID: UUID) async -> UUID? {
        await cleanupExpiredState()
        return primaryGeneralStreamIDs[sessionID]
    }

    // MARK: - Internal helpers

    internal func removeStream(id streamID: UUID) async {
        guard let meta = streamMeta.removeValue(forKey: streamID) else {
            return
        }

        // The hub finishes the continuation and force-closes a live sink.
        hub.remove(streamID: streamID)

        if var streamIDs = sessionStreams[meta.sessionID] {
            streamIDs.remove(streamID)
            if streamIDs.isEmpty {
                sessionStreams.removeValue(forKey: meta.sessionID)
            } else {
                sessionStreams[meta.sessionID] = streamIDs
            }
        }

        if primaryGeneralStreamIDs[meta.sessionID] == streamID {
            selectPrimaryGeneralStream(for: meta.sessionID, keepRetainedCurrent: false)
        }

        await updateSessionExpiry(for: meta.sessionID)
    }

    /// Pick the session's primary general stream. Synchronous — the hub is too —
    /// so this runs atomically within the actor, never interleaving with another
    /// stream mutation.
    internal func selectPrimaryGeneralStream(for sessionID: UUID, keepRetainedCurrent: Bool) {
        let currentPrimary = primaryGeneralStreamIDs[sessionID]
        let entries = (sessionStreams[sessionID] ?? [])
            .filter { streamMeta[$0]?.kind.isGeneral == true }
            .compactMap { id -> (id: UUID, info: SSEStreamInfo)? in
                guard let info = hub.info(streamID: id) else { return nil }
                return (id, info)
            }

        let activeGeneral = entries.filter { $0.info.isActive }
        if let replacement = activeGeneral.max(by: {
            ($0.info.lastConnectedAt ?? .distantPast) < ($1.info.lastConnectedAt ?? .distantPast)
        }) {
            primaryGeneralStreamIDs[sessionID] = replacement.id
            return
        }

        if keepRetainedCurrent,
           let currentPrimary,
           entries.contains(where: { $0.id == currentPrimary }) {
            primaryGeneralStreamIDs[sessionID] = currentPrimary
            return
        }

        if let retained = entries.max(by: { $0.info.lastActivityAt < $1.info.lastActivityAt }) {
            primaryGeneralStreamIDs[sessionID] = retained.id
        } else {
            primaryGeneralStreamIDs.removeValue(forKey: sessionID)
        }
    }
}
#endif
