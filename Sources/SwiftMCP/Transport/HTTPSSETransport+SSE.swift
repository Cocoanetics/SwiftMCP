#if Server
import Foundation

extension HTTPSSETransport {
    // MARK: - Handling SSE Connections

    func createSSEStream(sessionID: UUID, kind: SSEStreamKind) async -> (AsyncStream<Data>, StreamRouteResponseInfo) {
        await sessionManager.createStream(sessionID: sessionID, kind: kind)
    }

    func resumeSSEStream(
        sessionID: UUID,
        lastEventID: String
    ) async throws -> (AsyncStream<Data>, StreamRouteResponseInfo) {
        try await sessionManager.resumeStream(sessionID: sessionID, after: lastEventID)
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
