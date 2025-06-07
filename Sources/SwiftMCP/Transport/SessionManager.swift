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

    /// Returns the current number of active SSE channels.
    var channelCount: Int {
        sessions.values.filter { $0.channel != nil }.count
    }

    /// Retrieve or create a session for the given identifier.
    func session(id: UUID, transport: any Transport) -> Session {
        if let existing = sessions[id] {
            if existing.transport == nil {
                existing.transport = transport
            }
            return existing
        }

        let session = Session(id: id, transport: transport)
        sessions[id] = session
        return session
    }

    /// Register a new SSE channel.
    /// - Parameters:
    ///   - channel: The channel to register.
    ///   - id: The unique identifier for the channel.
    ///   - transport: Transport associated with the session.
    func register(channel: Channel, id: UUID, transport: any Transport) {
        let session = sessions[id] ?? Session(id: id, transport: transport, channel: channel)
        session.channel = channel
        if session.transport == nil {
            session.transport = transport
        }
        sessions[id] = session
    }

    /// Remove an SSE channel.
    /// - Parameter id: The unique identifier of the channel.
    /// - Returns: True if a channel was removed.
    @discardableResult
    func removeChannel(id: UUID) -> Bool {
        if let session = sessions[id] {
            session.channel = nil
            return true
        }
        return false
    }

    /// Broadcast an SSE message to all channels.
    /// - Parameter message: The SSE message to send.
    func broadcastSSE(_ message: SSEMessage) {
        for session in sessions.values {
            session.sendSSE(message)
        }
    }

    /// Retrieve the channel for a given session identifier.
    /// - Parameter sessionID: The session identifier.
    /// - Returns: The channel if found.
    func getChannel(for sessionID: UUID) -> Channel? {
        sessions[sessionID]?.channel
    }

    /// Close all channels and remove them.
    func stopAllChannels() {
        for session in sessions.values {
            if let channel = session.channel {
                channel.close(promise: nil)
                session.channel = nil
            }
        }
    }

    /// Check if there's an active SSE connection for a given session.
    /// - Parameter sessionID: The session identifier.
    /// - Returns: `true` if there's an active channel for this session.
    func hasActiveConnection(for sessionID: UUID) -> Bool {
        sessions[sessionID]?.channel?.isActive ?? false
    }

    /// Remove a session entirely.
    func removeSession(id: UUID) {
        sessions.removeValue(forKey: id)
    }
}
