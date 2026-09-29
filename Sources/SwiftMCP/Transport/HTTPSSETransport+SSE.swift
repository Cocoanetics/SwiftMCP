#if Server
import Foundation

extension HTTPSSETransport {
    // MARK: - Handling SSE Connections

    /// A stream for `session`'s client — `nil` once the session is gone, its client
    /// disconnected: see ``SessionManager/createStream(for:kind:resumable:)``.
    func createSSEStream(
        for session: Session,
        kind: SSEStreamKind,
        resumable: Bool = true
    ) async -> (AsyncStream<Data>, StreamRouteResponseInfo)? {
        await sessionManager.createStream(for: session, kind: kind, resumable: resumable)
    }

    func resumeSSEStream(
        for session: Session,
        lastEventID: String
    ) async throws -> (AsyncStream<Data>, StreamRouteResponseInfo) {
        try await sessionManager.resumeStream(for: session, after: lastEventID)
    }

    /// Send a message to a specific client.
    func sendSSE(_ message: SSEMessage, to sessionID: UUID) {
        Task {
            _ = await sessionManager.routeSSEMessage(message, sessionID: sessionID, preferredStreamID: nil)
        }
    }

    @discardableResult
    func routeSSEMessage(_ message: SSEMessage, sessionID: UUID, preferredStreamID: UUID?) async -> Bool {
        await sessionManager.routeSSEMessage(message, sessionID: sessionID, preferredStreamID: preferredStreamID)
    }

    @discardableResult
    func sendJSONRPC(_ message: JSONRPCMessage, to streamID: UUID) async throws -> Bool {
        try await sessionManager.sendJSONRPC(message, to: streamID)
    }

    func finishSSEStream(_ streamID: UUID) async {
        await sessionManager.finishStream(streamID: streamID)
    }
}
#endif
