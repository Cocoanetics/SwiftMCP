//
//  HTTPScopedConnection.swift
//  SwiftMCP
//
//  The per-session ``MCPScopedConnection`` surfaced by a connection-based
//  ``HTTPSSETransport``, plus a small actor registry that maps `Mcp-Session-Id`
//  sessions to their connections.
//

#if Server
import Foundation

/// One MCP session (`Mcp-Session-Id`) surfaced as an ``MCPScopedConnection``.
///
/// POST handlers push pre-gated frames in via ``deliver(_:)`` — each carrying a
/// `within` scope that binds the session and the POST's per-request SSE stream.
/// Outbound responses route to that stream through the existing SSE machinery,
/// the same path ``HTTPSSETransport/send(_:)`` uses for notifications.
final class HTTPScopedConnection: MCPScopedConnection, @unchecked Sendable {
    let sessionID: UUID
    private unowned let transport: HTTPSSETransport

    let scopedInbound: AsyncStream<MCPInboundFrame>
    private let inboundContinuation: AsyncStream<MCPInboundFrame>.Continuation

    init(sessionID: UUID, transport: HTTPSSETransport) {
        self.sessionID = sessionID
        self.transport = transport
        var continuation: AsyncStream<MCPInboundFrame>.Continuation!
        scopedInbound = AsyncStream { continuation = $0 }
        inboundContinuation = continuation
    }

    /// Hands serve a pre-gated POST frame to dispatch.
    func deliver(_ frame: MCPInboundFrame) {
        inboundContinuation.yield(frame)
    }

    /// Ends the inbound stream (session destroyed or transport stopped).
    func close() {
        inboundContinuation.finish()
    }

    /// Routes a server→client message to the frame's bound request stream, or the
    /// session's general stream when no request stream is in scope.
    func send(_ message: JSONRPCMessage) async throws {
        if let streamID = Session.currentStreamContext?.streamID {
            _ = try await transport.sendJSONRPC(message, to: streamID)
        } else {
            let data = try JSONRPCFrame.encode([message])
            let sse = SSEMessage(data: String(data: data, encoding: .utf8) ?? "")
            _ = await transport.routeSSEMessage(sse, sessionID: sessionID, preferredStreamID: nil)
        }
    }
}

/// Thread-safe registry mapping sessions to their ``HTTPScopedConnection``s.
actor HTTPConnectionRegistry {
    private var connections: [UUID: HTTPScopedConnection] = [:]

    /// Returns the connection for `sessionID`, creating one (flagged `isNew`) if
    /// absent so the caller can yield it to `connections`.
    func connection(
        for sessionID: UUID,
        transport: HTTPSSETransport
    ) -> (connection: HTTPScopedConnection, isNew: Bool) {
        if let existing = connections[sessionID] {
            return (existing, false)
        }
        let created = HTTPScopedConnection(sessionID: sessionID, transport: transport)
        connections[sessionID] = created
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
