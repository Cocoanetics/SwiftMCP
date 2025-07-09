//
//  SessionManager.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation
import NIO

actor SessionManager {
    private var sessions: [UUID: Session] = [:]
    private weak var transport: (any Transport)?

    // OAuth state management removed - using transparent proxy instead

    init(transport: (any Transport)? = nil) {
        self.transport = transport
    }

    /// Returns the current number of active SSE channels.
    var channelCount: Int {
        get async {
            var count = 0
            for session in sessions.values {
                if await session.channel != nil {
                    count += 1
                }
            }
            return count
        }
    }

    /// Retrieve or create a session for the given identifier.
    func session(id: UUID) async -> Session {
        if let existing = sessions[id] {
            if await existing.transport == nil {
                await existing.setTransport(transport)
            }
            return existing
        }

        let session = Session(id: id)
        await session.setTransport(transport)
        sessions[id] = session
        return session
    }

    /// Register a new SSE channel.
    /// - Parameters:
    ///   - channel: The channel to register.
    ///   - id: The unique identifier for the channel.
    ///   - transport: Transport associated with the session.
    func register(channel: Channel, id: UUID) async {
        let session: Session
        if let existing = sessions[id] {
            session = existing
        } else {
            session = Session(id: id, channel: channel)
        }

        await session.setChannel(channel)

        if await session.transport == nil {
            await session.setTransport(transport)
        }

        sessions[id] = session
    }

    /// Remove an SSE channel.
    /// - Parameter id: The unique identifier of the channel.
    /// - Returns: True if a channel was removed.
    @discardableResult
    func removeChannel(id: UUID) async -> Bool {
        if let session = sessions[id] {
            await session.setChannel(nil)
            return true
        }
        return false
    }

    /// Broadcast an SSE message to all channels.
    /// - Parameter message: The SSE message to send.
    func broadcastSSE(_ message: SSEMessage) async {
        for session in sessions.values {
            await session.sendSSE(message)
        }
    }

    /// Retrieve the channel for a given session identifier.
    /// - Parameter sessionID: The session identifier.
    /// - Returns: The channel if found.
    func getChannel(for sessionID: UUID) async -> Channel? {
        return await sessions[sessionID]?.channel
    }

    /// Close all channels and remove them.
    func stopAllChannels() async {
        for session in sessions.values {
            if let channel = await session.channel {
                channel.close(promise: nil)
                await session.setChannel(nil)
            }
        }
    }

    /// Close all channels and remove all sessions.
    func removeAllSessions() async {
        for session in sessions.values {
            if let channel = await session.channel {
                channel.close(promise: nil)
            }
        }
        sessions.removeAll()
    }

    /// Check if there's an active SSE connection for a given session.
    /// - Parameter sessionID: The session identifier.
    /// - Returns: `true` if there's an active channel for this session.
    func hasActiveConnection(for sessionID: UUID) async -> Bool {
        if let session = sessions[sessionID], let channel = await session.channel {
            return channel.isActive
        }
        return false
    }

    /// Remove a session entirely.
    func removeSession(id: UUID) {
        sessions.removeValue(forKey: id)
    }

    // MARK: - OAuth State Management (Removed - using transparent proxy)

    // MARK: - Token lookup

    /// Return the first session whose stored accessToken matches `token` and is not expired.
    func session(forToken token: String) async -> Session? {
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
    /// - Parameters:
    ///   - sessionID: The session identifier
    ///   - oauthConfiguration: The OAuth configuration to use for fetching user info
    func fetchAndStoreUserInfo(for sessionID: UUID, oauthConfiguration: OAuthConfiguration) async {
        guard let session = sessions[sessionID],
              let accessToken = await session.accessToken else {
            return
        }

        // Only fetch user info if we don't already have it
        if await session.userInfo == nil {
            if let userInfo = await oauthConfiguration.fetchUserInfo(token: accessToken) {
                await session.setUserInfo(userInfo)
            }
        }
    }

    /// Broadcast a log message to all sessions, filtered by their minimumLogLevel.
    /// - Parameter message: The log message to send.
    func broadcastLog(_ message: LogMessage) async {
        for session in sessions.values {
            await session.sendLogNotification(message)
        }
    }
}
