#if Server
import Foundation
import NIOCore

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

    /// Register the NIO channel for an SSE stream and set up close handling.
    /// Called by `HTTPHandler` after the route handler returns a streaming response.
    func registerSSEChannel(_ channel: Channel, sessionID: UUID, streamID: UUID) {
        Task {
            guard let connectionToken = await sessionManager.register(
                channel: channel,
                sessionID: sessionID,
                streamID: streamID
            ) else {
                return
            }
            let count = await sessionManager.channelCount
            logger.info("New SSE channel registered (total: \(count))")

            channel.closeFuture.whenComplete { [weak self] _ in
                guard let self = self else { return }
                Task {
                    await self.sessionManager.markStreamDisconnected(
                        streamID: streamID,
                        connectionToken: connectionToken
                    )
                    let count = await self.sessionManager.channelCount
                    self.logger.info("SSE channel removed (remaining: \(count))")
                }
            }
        }
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
