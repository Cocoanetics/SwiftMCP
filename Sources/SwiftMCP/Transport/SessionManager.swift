import Foundation
import NIO

actor SessionManager {
    private struct BufferedEvent {
        let id: String
        let payload: Data
    }

    private struct StreamRecord {
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
    internal let pendingUploadStore: PendingUploadStore?
    internal let retentionInterval: TimeInterval

    private var streams: [UUID: StreamRecord] = [:]
    private var sessionStreams: [UUID: Set<UUID>] = [:]
    private var primaryGeneralStreamIDs: [UUID: UUID] = [:]
    private let eventBufferCapacity = 256

    init(
        transport: (any Transport)? = nil,
        pendingUploadStore: PendingUploadStore? = nil,
        retentionInterval: TimeInterval = 5 * 60
    ) {
        self.transport = transport
        self.pendingUploadStore = pendingUploadStore
        self.retentionInterval = retentionInterval
    }

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

    /// Check whether a session with the given identifier exists.
    func hasSession(id: UUID) async -> Bool {
        await cleanupExpiredState()
        return sessions[id] != nil
    }

    /// Retrieve an existing session without creating a new one.
    func existingSession(id: UUID) async -> Session? {
        await cleanupExpiredState()
        guard let existing = sessions[id] else {
            return nil
        }

        if await existing.transport == nil {
            await existing.setTransport(transport)
        }

        return existing
    }

    /// Retrieve or create a session for the given identifier.
    func session(id: UUID) async -> Session {
        await cleanupExpiredState()
        if let existing = await existingSession(id: id) {
            await existing.touchActivity()
            return existing
        }

        let session = Session(id: id)
        await session.setTransport(transport)
        await session.touchActivity()
        sessions[id] = session
        return session
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
    func resumeStream(sessionID: UUID, after lastEventID: String) async throws -> (AsyncStream<Data>, StreamRouteResponseInfo) {
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

    /// Broadcast an SSE message to all currently active streams.
    /// - Parameter message: The SSE message to send.
    func broadcastSSE(_ message: SSEMessage) async {
        await cleanupExpiredState()
        let activeStreamIDs = streams.values.filter(\.isActive).map(\.id)
        for streamID in activeStreamIDs {
            _ = await sendSSE(message, to: streamID)
        }
    }

    /// Return all active stream identifiers.
    func activeStreamIDs() async -> [UUID] {
        await cleanupExpiredState()
        return streams.values.filter(\.isActive).map(\.id)
    }

    /// Enumerate all sessions and call the provided block for each one.
    /// The session context is activated for each call.
    @discardableResult
    func forEachSession<T: Sendable>(_ block: @Sendable @escaping (Session) async throws -> T) async rethrows -> [T] {
        await cleanupExpiredState()
        var results: [T] = []
        for session in sessions.values {
            let result = try await session.work { session in
                try await block(session)
            }
            results.append(result)
        }
        return results
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

    /// Close all channels and remove all sessions and streams.
    func removeAllSessions() async {
        let sessionIDs = Array(sessions.keys)
        for sessionID in sessionIDs {
            await removeSession(id: sessionID)
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

    /// Remove a session entirely, including all retained streams and pending state.
    func removeSession(id: UUID) async {
        await cleanupExpiredState()
        await destroySession(id: id)
    }

    /// Get all session IDs.
    var sessionIDs: [UUID] {
        Array(sessions.keys)
    }

    // MARK: - Token lookup

    /// Return the first session whose stored accessToken matches `token` and is not expired.
    func session(forToken token: String) async -> Session? {
        await cleanupExpiredState()
        for session in sessions.values {
            if let stored = await session.accessToken,
               stored == token,
               (await session.accessTokenExpiry ?? Date.distantFuture) > Date() {
                return session
            }
        }
        return nil
    }

    /// Fetch and store user info for a session after token validation.
    func fetchAndStoreUserInfo(for sessionID: UUID, oauthConfiguration: OAuthConfiguration) async {
        guard let session = sessions[sessionID],
              let accessToken = await session.accessToken else {
            return
        }

        if await session.userInfo == nil {
            if let userInfo = await oauthConfiguration.fetchUserInfo(token: accessToken) {
                await session.setUserInfo(userInfo)
            }
        }
    }

    /// Broadcast a log message to all sessions, filtered by their minimumLogLevel.
    func broadcastLog(_ message: LogMessage) async {
        await cleanupExpiredState()
        for session in sessions.values {
            await session.work { session in
                await session.sendLogNotification(message)
            }
        }
    }

    /// Broadcast a tools list-changed notification to all sessions.
    func broadcastToolsListChanged() async {
        await cleanupExpiredState()
        for session in sessions.values {
            await session.work { session in
                try? await session.sendToolListChanged()
            }
        }
    }

    /// Broadcast a resources list-changed notification to all sessions.
    func broadcastResourcesListChanged() async {
        await cleanupExpiredState()
        for session in sessions.values {
            await session.work { session in
                try? await session.sendResourceListChanged()
            }
        }
    }

    /// Broadcast a prompts list-changed notification to all sessions.
    func broadcastPromptsListChanged() async {
        await cleanupExpiredState()
        for session in sessions.values {
            await session.work { session in
                try? await session.sendPromptListChanged()
            }
        }
    }

    /// Send a resource-updated notification to all sessions subscribed to the given URI.
    func broadcastResourceUpdated(uri: URL) async {
        await cleanupExpiredState()
        let uriString = uri.absoluteString
        for session in sessions.values {
            let subscribed = await session.isSubscribedToResource(uri: uriString)
            if subscribed {
                await session.work { session in
                    try? await session.sendResourceUpdated(uri: uri)
                }
            }
        }
    }

    /// Route an already-encoded JSON-RPC message to a specific stream.
    @discardableResult
    func sendJSONRPC(_ message: JSONRPCMessage, to streamID: UUID) async throws -> Bool {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithTimeZone
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(message)
        let text = String(data: data, encoding: .utf8) ?? ""
        return await sendSSE(SSEMessage(data: text), to: streamID)
    }

    /// Route an SSE message to a preferred stream or the session's primary general stream.
    @discardableResult
    func routeSSEMessage(_ message: SSEMessage, sessionID: UUID, preferredStreamID: UUID?) async -> Bool {
        await cleanupExpiredState()

        if let preferredStreamID,
           let record = streams[preferredStreamID],
           record.sessionID == sessionID {
            return await sendSSE(message, to: preferredStreamID)
        }

        guard let primaryStreamID = primaryGeneralStreamIDs[sessionID] else {
            return false
        }

        return await sendSSE(message, to: primaryStreamID)
    }

    @discardableResult
    func sendComment(_ comment: String, to streamID: UUID) async -> Bool {
        await sendSSE(SSEMessage(comment: comment), to: streamID)
    }

    // MARK: - Internal routing helpers

    @discardableResult
    private func sendSSE(_ message: SSEMessage, to streamID: UUID) async -> Bool {
        guard var record = streams[streamID] else {
            return false
        }
        guard !record.isCompleted || record.kind.isGeneral else {
            return false
        }

        var outbound = message
        if record.kind != .legacyGeneral, outbound.isReplayableDataEvent {
            if outbound.id == nil {
                outbound.id = makeEventID(streamID: streamID, sequence: record.nextSequence)
                record.nextSequence += 1
            }

            let payload = Data(outbound.description.utf8)
            record.buffer.append(BufferedEvent(id: outbound.id!, payload: payload))
            if record.buffer.count > eventBufferCapacity {
                record.buffer.removeFirst(record.buffer.count - eventBufferCapacity)
            }
            record.continuation?.yield(payload)
        } else {
            record.continuation?.yield(Data(outbound.description.utf8))
        }

        record.lastActivityAt = Date()
        streams[streamID] = record

        if let session = sessions[record.sessionID] {
            await session.touchActivity()
        }

        return true
    }

    private func sendPrimingEvent(to streamID: UUID) async {
        guard var record = streams[streamID] else {
            return
        }

        let eventID = makeEventID(streamID: streamID, sequence: record.nextSequence)
        record.nextSequence += 1
        streams[streamID] = record
        _ = await sendSSE(SSEMessage(data: "", id: eventID), to: streamID)
    }

    private func cleanupExpiredState() async {
        let now = Date()

        let expiredStreamIDs = streams.compactMap { streamID, record in
            if let expiresAt = record.expiresAt, expiresAt <= now {
                return streamID
            }
            return nil
        }
        for streamID in expiredStreamIDs {
            await removeStream(id: streamID)
        }

        let expiredSessionIDs = sessions.compactMap { sessionID, session in
            sessionID
        }
        for sessionID in expiredSessionIDs {
            guard let session = sessions[sessionID] else { continue }
            if let expiresAt = await session.expiresAt, expiresAt <= now {
                await destroySession(id: sessionID)
            }
        }

        await pendingUploadStore?.expireEarlyArrivals(olderThan: retentionInterval)
    }

    private func removeStream(id streamID: UUID) async {
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

    private func destroySession(id sessionID: UUID) async {
        let streamIDs = Array(sessionStreams[sessionID] ?? [])
        for streamID in streamIDs {
            await removeStream(id: streamID)
        }

        if let session = sessions.removeValue(forKey: sessionID) {
            await session.cancelAllWaitingTasks()
        }

        await pendingUploadStore?.cancelAll(sessionID: sessionID, error: CancellationError())
        primaryGeneralStreamIDs.removeValue(forKey: sessionID)
        sessionStreams.removeValue(forKey: sessionID)
    }

    private func updateSessionExpiry(for sessionID: UUID) async {
        guard let session = sessions[sessionID] else {
            return
        }

        let streamIDs = sessionStreams[sessionID] ?? []
        if streamIDs.isEmpty {
            let lastActivity = await session.lastActivityAt
            await session.setExpiresAt(lastActivity.addingTimeInterval(retentionInterval))
            return
        }

        let activeExists = streamIDs.contains { streams[$0]?.isActive == true }
        if activeExists {
            await session.setExpiresAt(nil)
            return
        }

        let latestStreamExpiry = streamIDs.compactMap { streams[$0]?.expiresAt }.max()
        let sessionExpiry = (await session.lastActivityAt).addingTimeInterval(retentionInterval)
        await session.setExpiresAt(max(sessionExpiry, latestStreamExpiry ?? sessionExpiry))
    }

    private func selectPrimaryGeneralStream(for sessionID: UUID, keepRetainedCurrent: Bool) {
        let currentPrimary = primaryGeneralStreamIDs[sessionID]
        let generalStreams = (sessionStreams[sessionID] ?? [])
            .compactMap { streams[$0] }
            .filter { $0.kind.isGeneral }

        let activeGeneral = generalStreams.filter(\.isActive)
        if let replacement = activeGeneral.max(by: { ($0.lastConnectedAt ?? .distantPast) < ($1.lastConnectedAt ?? .distantPast) }) {
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

    private func parseEventID(_ value: String) throws -> (streamID: UUID, sequence: Int) {
        guard let separatorIndex = value.lastIndex(of: ":") else {
            throw StreamResumeError.malformedEventID
        }

        let streamPart = String(value[..<separatorIndex])
        let sequencePart = String(value[value.index(after: separatorIndex)...])

        guard let streamID = UUID(uuidString: streamPart),
              let sequence = Int(sequencePart),
              sequence >= 1 else {
            throw StreamResumeError.malformedEventID
        }

        return (streamID, sequence)
    }

    private func makeEventID(streamID: UUID, sequence: Int) -> String {
        "\(streamID.uuidString):\(sequence)"
    }
}
