#if Server
import Foundation

extension SessionManager {
    /// Broadcast an SSE message to every session, routing to each session's primary general stream.
    /// Messages for sessions whose channel is currently disconnected are buffered for replay on resume.
    func broadcastSSE(_ message: SSEMessage) async {
        await cleanupExpiredState()
        let sessionIDs = Array(sessions.keys)
        for sessionID in sessionIDs {
            _ = await routeSSEMessage(message, sessionID: sessionID, preferredStreamID: nil)
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
        let data = try JSONRPCMessage.makeEncoder().encode(message)
        let text = String(data: data, encoding: .utf8) ?? ""
        return await sendSSE(SSEMessage(data: text), to: streamID)
    }

    /// Route an SSE message to a preferred stream or the session's primary general stream.
    @discardableResult
    func routeSSEMessage(_ message: SSEMessage, sessionID: UUID, preferredStreamID: UUID?) async -> Bool {
        await cleanupExpiredState()

        if let preferredStreamID,
           streamMeta[preferredStreamID]?.sessionID == sessionID {
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

    /// Hand a message to the hub (which buffers/ids replayable data events and the
    /// completion guard), then touch the owning session's activity if it was sent.
    @discardableResult
    internal func sendSSE(_ message: SSEMessage, to streamID: UUID) async -> Bool {
        guard let meta = streamMeta[streamID] else {
            return false
        }
        let sent = hub.send(message, to: streamID)
        if sent, let session = sessions[meta.sessionID] {
            await session.touchActivity()
        }
        return sent
    }
}
#endif
