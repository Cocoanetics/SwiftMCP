import Foundation

extension SessionManager {
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

    /// Close all channels and remove all sessions and streams.
    func removeAllSessions() async {
        let sessionIDs = Array(sessions.keys)
        for sessionID in sessionIDs {
            await removeSession(id: sessionID)
        }
    }

    /// Remove a session entirely, including all retained streams and pending state.
    func removeSession(id: UUID) async {
        await cleanupExpiredState()
        await destroySession(id: id)
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

    // MARK: - Internal helpers

    internal func destroySession(id sessionID: UUID) async {
        let streamIDs = Array(sessionStreams[sessionID] ?? [])
        for streamID in streamIDs {
            await removeStream(id: streamID)
        }

        if let session = sessions.removeValue(forKey: sessionID) {
            await session.cancelAllWaitingTasks()
        }

        primaryGeneralStreamIDs.removeValue(forKey: sessionID)
        sessionStreams.removeValue(forKey: sessionID)
    }

    internal func updateSessionExpiry(for sessionID: UUID) async {
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

    internal func cleanupExpiredState() async {
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

        let expiredSessionIDs = sessions.compactMap { sessionID, _ in
            sessionID
        }
        for sessionID in expiredSessionIDs {
            guard let session = sessions[sessionID] else { continue }
            if let expiresAt = await session.expiresAt, expiresAt <= now {
                await destroySession(id: sessionID)
            }
        }
    }
}
