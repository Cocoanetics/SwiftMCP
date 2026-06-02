#if Server
import Foundation
import NIO

extension SessionManager {
    /// Returns the current number of active SSE channels.
    var channelCount: Int {
        get async {
            await cleanupExpiredState()
            return streams.values.reduce(into: 0) { count, record in
                if record.channel != nil {
                    count += 1
                }
            }
        }
    }

    /// Create a new SSE stream for the given session and return the AsyncStream to write to the response.
    func createStream(sessionID: UUID, kind: SSEStreamKind) async -> (AsyncStream<Data>, StreamRouteResponseInfo) {
        await cleanupExpiredState()
        let session = await session(id: sessionID)
        await session.touchActivity()

        let streamID = UUID()
        let (stream, continuation) = AsyncStream<Data>.makeStream()

        var record = StreamRecord(id: streamID, sessionID: sessionID, kind: kind, continuation: continuation)
        record.lastConnectedAt = Date()
        streams[streamID] = record
        sessionStreams[sessionID, default: []].insert(streamID)

        if kind.isGeneral {
            primaryGeneralStreamIDs[sessionID] = streamID
        }

        if kind != .legacyGeneral {
            await sendPrimingEvent(to: streamID)
        }

        return (stream, StreamRouteResponseInfo(sessionID: sessionID, streamID: streamID))
    }

    /// Resume an existing retained stream from the specified Last-Event-ID.
    func resumeStream(
        sessionID: UUID,
        after lastEventID: String
    ) async throws -> (AsyncStream<Data>, StreamRouteResponseInfo) {
        await cleanupExpiredState()

        let parsed = try parseEventID(lastEventID)
        guard var record = streams[parsed.streamID] else {
            throw StreamResumeError.unknownStream
        }
        guard record.sessionID == sessionID else {
            throw StreamResumeError.sessionMismatch
        }
        guard let replayIndex = record.buffer.firstIndex(where: { $0.id == lastEventID }) else {
            throw StreamResumeError.resumePointUnavailable
        }

        record.continuation?.finish()

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        record.continuation = continuation
        record.channel = nil
        record.connectionToken = nil
        record.expiresAt = nil
        record.lastConnectedAt = Date()
        record.lastActivityAt = Date()
        streams[parsed.streamID] = record

        if let session = sessions[sessionID] {
            await session.touchActivity()
        }

        for buffered in record.buffer[(replayIndex + 1)...] {
            continuation.yield(buffered.payload)
        }

        if record.isCompleted {
            continuation.finish()
            await markStreamDisconnected(streamID: parsed.streamID, connectionToken: nil)
        }

        return (stream, StreamRouteResponseInfo(sessionID: sessionID, streamID: parsed.streamID))
    }

    /// Register a new SSE channel for a specific stream.
    func register(channel: Channel, sessionID: UUID, streamID: UUID) async -> UUID? {
        await cleanupExpiredState()
        guard var record = streams[streamID], record.sessionID == sessionID else {
            return nil
        }

        let connectionToken = UUID()
        record.channel = channel
        record.connectionToken = connectionToken
        record.expiresAt = nil
        record.lastConnectedAt = Date()
        streams[streamID] = record

        if record.kind.isGeneral {
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
        guard var record = streams[streamID] else {
            return
        }
        if let connectionToken, record.connectionToken != connectionToken {
            return
        }

        record.continuation?.finish()
        record.continuation = nil
        record.channel = nil
        record.connectionToken = nil
        record.expiresAt = Date().addingTimeInterval(retentionInterval)
        record.lastActivityAt = Date()
        streams[streamID] = record

        if record.kind.isGeneral {
            selectPrimaryGeneralStream(for: record.sessionID, keepRetainedCurrent: true)
        }

        await updateSessionExpiry(for: record.sessionID)
    }

    /// Finish a stream after the server has emitted its terminal response.
    func finishStream(streamID: UUID) async {
        await cleanupExpiredState()
        guard var record = streams[streamID] else {
            return
        }

        record.isCompleted = true
        record.expiresAt = Date().addingTimeInterval(retentionInterval)
        record.lastActivityAt = Date()
        record.continuation?.finish()
        record.continuation = nil
        record.channel = nil
        record.connectionToken = nil
        streams[streamID] = record

        if record.kind.isGeneral {
            selectPrimaryGeneralStream(for: record.sessionID, keepRetainedCurrent: true)
        }

        await updateSessionExpiry(for: record.sessionID)
    }

    /// Return all active stream identifiers.
    func activeStreamIDs() async -> [UUID] {
        await cleanupExpiredState()
        return streams.values.filter(\.isActive).map(\.id)
    }

    /// Retrieve the primary general channel for a given session identifier.
    func getChannel(for sessionID: UUID) async -> Channel? {
        await cleanupExpiredState()
        guard let streamID = primaryGeneralStreamIDs[sessionID] else {
            return nil
        }
        return streams[streamID]?.channel
    }

    /// Close all active channels without removing retained state.
    func stopAllChannels() async {
        let activeChannels = streams.values.compactMap(\.channel)
        for channel in activeChannels {
            channel.close(promise: nil)
        }
    }

    /// Check if any stream for a session is currently active.
    func hasActiveConnection(for sessionID: UUID) async -> Bool {
        await cleanupExpiredState()
        guard let streamIDs = sessionStreams[sessionID] else {
            return false
        }
        return streamIDs.contains { streams[$0]?.isActive == true }
    }

    /// Check whether the primary general stream is currently active.
    func hasActivePrimaryGeneralConnection(for sessionID: UUID) async -> Bool {
        await cleanupExpiredState()
        guard let streamID = primaryGeneralStreamIDs[sessionID] else {
            return false
        }
        return streams[streamID]?.isActive == true
    }

    func primaryGeneralStreamID(for sessionID: UUID) async -> UUID? {
        await cleanupExpiredState()
        return primaryGeneralStreamIDs[sessionID]
    }

    // MARK: - Internal helpers

    internal func removeStream(id streamID: UUID) async {
        guard let record = streams.removeValue(forKey: streamID) else {
            return
        }

        record.continuation?.finish()
        if let channel = record.channel, channel.isActive {
            channel.close(promise: nil)
        }

        if var streamIDs = sessionStreams[record.sessionID] {
            streamIDs.remove(streamID)
            if streamIDs.isEmpty {
                sessionStreams.removeValue(forKey: record.sessionID)
            } else {
                sessionStreams[record.sessionID] = streamIDs
            }
        }

        if primaryGeneralStreamIDs[record.sessionID] == streamID {
            selectPrimaryGeneralStream(for: record.sessionID, keepRetainedCurrent: false)
        }

        await updateSessionExpiry(for: record.sessionID)
    }

    internal func selectPrimaryGeneralStream(for sessionID: UUID, keepRetainedCurrent: Bool) {
        let currentPrimary = primaryGeneralStreamIDs[sessionID]
        let generalStreams = (sessionStreams[sessionID] ?? [])
            .compactMap { streams[$0] }
            .filter { $0.kind.isGeneral }

        let activeGeneral = generalStreams.filter(\.isActive)
        if let replacement = activeGeneral.max(by: {
            ($0.lastConnectedAt ?? .distantPast) < ($1.lastConnectedAt ?? .distantPast)
        }) {
            primaryGeneralStreamIDs[sessionID] = replacement.id
            return
        }

        if keepRetainedCurrent,
           let currentPrimary,
           generalStreams.contains(where: { $0.id == currentPrimary }) {
            primaryGeneralStreamIDs[sessionID] = currentPrimary
            return
        }

        if let retained = generalStreams.max(by: { $0.lastActivityAt < $1.lastActivityAt }) {
            primaryGeneralStreamIDs[sessionID] = retained.id
        } else {
            primaryGeneralStreamIDs.removeValue(forKey: sessionID)
        }
    }
}
#endif
