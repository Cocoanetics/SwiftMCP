//
//  SSEChannelManager.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation
import NIO

actor SSEChannelManager {
    private var sseChannels: [UUID: Channel] = [:]

/// Returns the current number of active SSE channels.
    var channelCount: Int {
        sseChannels.count
    }

/// Register a new SSE channel.
/// - Parameters:
///   - channel: The channel to register.
///   - id: The unique identifier for the channel.
    func register(channel: Channel, id: UUID) {
// Only register if the channel isn't already present.
        guard sseChannels[id] == nil else { return }
        sseChannels[id] = channel
    }

/// Remove an SSE channel.
/// - Parameter id: The unique identifier of the channel.
/// - Returns: True if a channel was removed.
    @discardableResult
    func removeChannel(id: UUID) -> Bool {
        if sseChannels.removeValue(forKey: id) != nil {
            return true
        }
        return false
    }

/// Broadcast an SSE message to all channels.
/// - Parameter message: The SSE message to send.
    func broadcastSSE(_ message: SSEMessage) {
        for channel in sseChannels.values {
            channel.sendSSE(message)
        }
    }

/// Send an SSE message to a channel identified by a clientId string.
/// - Parameters:
///   - message: The SSE message to send.
///   - clientIdString: The string that can be converted to a UUID.
    func sendSSE(_ message: SSEMessage, to clientIdString: String) {
        guard let uuid = UUID(uuidString: clientIdString),
              let channel = sseChannels[uuid],
              channel.isActive else { return }
        channel.sendSSE(message)
    }

/// Retrieve the channel for a given client identifier.
/// - Parameter clientIdString: The string representation of the UUID.
/// - Returns: The channel if found.
    func getChannel(for clientIdString: String) -> Channel? {
        guard let uuid = UUID(uuidString: clientIdString) else { return nil }
        return sseChannels[uuid]
    }

/// Close all channels and remove them.
    func stopAllChannels() {
        for channel in sseChannels.values {
            channel.close(promise: nil)
        }
        sseChannels.removeAll()
    }

/// Check if there's an active SSE connection for a given client.
/// - Parameter clientIdString: The string representation of the UUID.
/// - Returns: True if there's an active channel for this client.
    func hasActiveConnection(for clientIdString: String) -> Bool {
        guard let uuid = UUID(uuidString: clientIdString),
              let channel = sseChannels[uuid] else { return false }
        return channel.isActive
    }
}
