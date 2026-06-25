//
//  MCPScopedConnection.swift
//  SwiftMCP
//
//  A connection whose frames carry their own session + outbound scope, for
//  transports where the session and its reply destination are established
//  *before* dispatch (HTTP+SSE: a session per `Mcp-Session-Id`, a per-request SSE
//  stream per POST). Gated behind `Server` alongside the rest of the serving
//  stack.
//

#if Server
import Foundation

/// One inbound JSON-RPC frame plus the connection's outbound scope for it.
///
/// A scoped connection hands ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``
/// frames that are already gated and already know where their replies go. `serve`
/// runs each frame's dispatch inside ``within``, which binds the correct
/// `Session.current` (and, for HTTP+SSE, the per-request SSE stream via
/// `Session.taskStreamContext`) and tears the scope down afterward.
public struct MCPInboundFrame: Sendable {
    /// The decoded messages of one wire frame (one POST body; a batch is several).
    public let messages: [JSONRPCMessage]

    /// Runs `operation` inside this frame's session/outbound scope.
    ///
    /// The connection binds `Session.current` (and any per-request routing
    /// context) for the duration, so the server's responses and mid-call
    /// notifications route to the right place, then cleans up (e.g. finishing the
    /// request's SSE stream).
    public let within: @Sendable (_ operation: @Sendable () async -> Void) async -> Void

    public init(
        _ messages: [JSONRPCMessage],
        within: @escaping @Sendable (_ operation: @Sendable () async -> Void) async -> Void
    ) {
        self.messages = messages
        self.within = within
    }
}

/// A connection that owns its `Session` and supplies a per-frame scope, rather
/// than letting `serve` mint a session and a single outbound sink.
///
/// This is the boundary HTTP+SSE needs: by the time a POST is dispatched the
/// transport has already created/looked-up the session (by `Mcp-Session-Id`),
/// bound its bearer token, negotiated the protocol version, and opened the
/// per-request SSE stream — all state that lives on *its* session, established
/// before `serve` sees the frame. A scoped connection therefore delivers
/// pre-gated ``MCPInboundFrame``s; `serve` is a pure pump that runs
/// ``MCPServer/processBatch(_:ignoringEmptyResponses:)`` inside each frame's
/// ``MCPInboundFrame/within`` and writes responses back through ``send(_:)``.
public protocol MCPScopedConnection: MCPConnection {
    /// Pre-gated inbound frames, each carrying its own session/outbound scope.
    var scopedInbound: AsyncStream<MCPInboundFrame> { get }
}

public extension MCPScopedConnection {
    /// A scoped connection is driven through ``scopedInbound``; the plain
    /// single-message ``MCPConnection/inbound`` is unused, so it finishes
    /// immediately to satisfy the conformance.
    var inbound: AsyncStream<JSONRPCMessage> {
        AsyncStream { $0.finish() }
    }
}
#endif
