//
//  HTTPScopedConnection.swift
//  SwiftMCP
//
//  The per-session ``MCPConnection`` surfaced by a connection-based
//  ``HTTPSSETransport``, plus a small actor registry that maps `Mcp-Session-Id`
//  sessions to their connections.
//

#if Server
import Foundation

/// One MCP session (`Mcp-Session-Id`) surfaced as an ``MCPConnection``.
///
/// Unlike a one-socket ``BasicConnection``, this connection's session is the
/// transport's own (`HTTPSSETransport` attaches itself as the session's
/// transport), and each POST arrives as an ``MCPInboundFrame`` whose `within`
/// scope binds the POST's per-request SSE stream. Outbound responses are routed
/// to that stream via the existing SSE machinery — the same path
/// ``HTTPSSETransport/send(_:)`` uses for notifications.
final class HTTPScopedConnection: MCPConnection, @unchecked Sendable {
    let session: Session
    private unowned let transport: HTTPSSETransport

    let inbound: AsyncStream<MCPInboundFrame>
    private let inboundContinuation: AsyncStream<MCPInboundFrame>.Continuation

    init(session: Session, transport: HTTPSSETransport) {
        self.session = session
        self.transport = transport
        var continuation: AsyncStream<MCPInboundFrame>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        inboundContinuation = continuation
    }

    /// Hands serve a pre-gated POST frame (with its per-request stream scope).
    func deliver(_ frame: MCPInboundFrame) {
        inboundContinuation.yield(frame)
    }

    /// Ends the inbound stream (session destroyed or transport stopped).
    func close() {
        inboundContinuation.finish()
    }

    /// Routes each message of the frame to the bound request stream (one SSE event
    /// per message), or the session's general stream when no request stream is in
    /// scope.
    func send(_ frame: [JSONRPCMessage]) async throws {
        for message in frame {
            if let streamID = Session.currentStreamContext?.streamID {
                _ = try await transport.sendJSONRPC(message, to: streamID)
            } else {
                let data = try JSONRPCFrame.encode([message])
                let sse = SSEMessage(data: String(data: data, encoding: .utf8) ?? "")
                _ = await transport.routeSSEMessage(sse, sessionID: session.id, preferredStreamID: nil)
            }
        }
    }
}

/// Thread-safe registry mapping sessions to their ``HTTPScopedConnection``s.
actor HTTPConnectionRegistry {
    private var connections: [UUID: HTTPScopedConnection] = [:]

    /// Returns the connection for `session`, creating one (flagged `isNew`) if
    /// absent so the caller can yield it to `connections`.
    func connection(
        for session: Session,
        transport: HTTPSSETransport
    ) -> (connection: HTTPScopedConnection, isNew: Bool) {
        if let existing = connections[session.id] {
            return (existing, false)
        }
        let created = HTTPScopedConnection(session: session, transport: transport)
        connections[session.id] = created
        return (created, true)
    }

    /// Closes and forgets the connection for a session (DELETE / retention).
    func remove(_ sessionID: UUID) {
        connections.removeValue(forKey: sessionID)?.close()
    }

    /// Closes and forgets every connection (transport stop).
    func closeAll() {
        for connection in connections.values {
            connection.close()
        }
        connections.removeAll()
    }
}
#endif
