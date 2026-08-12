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
    ///
    /// Routing failures are counted and logged (once per session per outage): a
    /// subscribed session with no routable general stream used to drop the
    /// notification without a trace, leaving a healthy-looking session that
    /// never receives another push (the zombie-session incident).
    func broadcastResourceUpdated(uri: URL) async {
        await cleanupExpiredState()
        let uriString = uri.absoluteString
        for session in sessions.values {
            guard await session.isSubscribedToResource(uri: uriString) else { continue }

            let notification = JSONRPCMessage.notification(
                method: "notifications/resources/updated",
                params: ["uri": .string(uriString)]
            )
            let routed = await routeJSONRPC(notification, sessionID: session.id)
            recordResourceUpdatedOutcome(routed: routed, sessionID: session.id, uri: uriString)
        }
    }

    /// Encode and route a JSON-RPC message to the session's primary general
    /// stream, reporting whether any stream accepted it.
    @discardableResult
    internal func routeJSONRPC(_ message: JSONRPCMessage, sessionID: UUID) async -> Bool {
        guard let data = try? JSONRPCMessage.makeEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else {
            return false
        }
        return await routeSSEMessage(SSEMessage(data: text), sessionID: sessionID, preferredStreamID: nil)
    }

    /// Track per-session delivery of resource-updated broadcasts, logging the
    /// transitions (first drop, later recovery) rather than every occurrence.
    private func recordResourceUpdatedOutcome(routed: Bool, sessionID: UUID, uri: String) {
        if routed {
            if sessionsWithUndeliverableBroadcast.remove(sessionID) != nil {
                logger.info("resource-updated delivery recovered for session \(sessionID)")
            }
            return
        }

        undeliverableBroadcastCount += 1
        if sessionsWithUndeliverableBroadcast.insert(sessionID).inserted {
            let details = "resource-updated for \(uri) dropped: session \(sessionID) is subscribed"
                + " but has no routable general SSE stream; dropping until one (re)connects"
            logger.warning("\(details)")
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
            logger.debug("No primary general stream for session \(sessionID); SSE message not routed")
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
