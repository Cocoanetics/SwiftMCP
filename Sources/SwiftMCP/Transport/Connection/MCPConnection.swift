//
//  MCPConnection.swift
//  SwiftMCP
//
//  The JSON-RPC duplex at the transport ↔ server boundary. See the
//  <doc:Connection-Based-Transports> article for the full picture.
//

import Foundation

/// A single full-duplex JSON-RPC channel to one client, owning the ``Session``
/// its traffic belongs to.
///
/// A ``MCPTransport`` is a *source* of connections; each connection is one
/// JSON-RPC conversation. The connection owns its ``session`` and provides the
/// outbound scope for each inbound frame.
/// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` is a pure pump: it
/// binds the connection's session, gates each frame, and runs the server inside
/// the frame's ``MCPInboundFrame/within`` scope — never minting a session of its
/// own. That single contract covers a one-socket transport (stdio, TCP) and one
/// whose session spans many connections (HTTP+SSE: a session per
/// `Mcp-Session-Id`, a per-request SSE stream per POST) alike.
///
/// For a one-socket transport, ``BasicConnection`` supplies the whole shape — a
/// fresh session whose outbound is wired back to the transport — so the transport
/// only feeds decoded frames and writes bytes.
///
/// ## Frames
///
/// The unit of transfer is a *frame*: an array of ``JSONRPCMessage``. A single
/// message is a one-element frame; a JSON-RPC batch is a multi-element frame that
/// round-trips as one payload (batching was removed in MCP `2025-06-18`, so most
/// frames are single).
public protocol MCPConnection: Sendable {
    /// The session this connection's traffic belongs to. The connection owns its
    /// lifetime; `serve` binds it as `Session.current` while pumping.
    var session: Session { get }

    /// Inbound JSON-RPC frames, each carrying the connection's outbound scope for
    /// it. The stream finishes when the client disconnects or the transport
    /// stops, ending the per-connection routing loop.
    var inbound: AsyncStream<MCPInboundFrame> { get }

    /// Sends a JSON-RPC frame to the client.
    ///
    /// Responses, and server→client pushes (notifications, `sampling`/`roots`
    /// requests), travel through here. A one-socket transport writes the frame as
    /// one payload; HTTP+SSE delivers each message as its own SSE event.
    ///
    /// - Parameter frame: One or more JSON-RPC messages to deliver.
    /// - Throws: A transport-specific error if the frame cannot be written.
    func send(_ frame: [JSONRPCMessage]) async throws
}

public extension MCPConnection {
    /// Convenience for sending a single message as a one-element frame.
    func send(_ message: JSONRPCMessage) async throws {
        try await send([message])
    }
}

/// One inbound JSON-RPC frame plus the connection's outbound scope for it.
///
/// `serve` runs each frame's dispatch inside ``within``. For a one-socket
/// transport that scope is a pass-through (the default). HTTP+SSE uses it to bind
/// the POST's per-request SSE stream (via `Session.taskStreamContext`) so the
/// response and any mid-call notifications land on it, then tears the stream down
/// — without leaking any HTTP type into this core boundary.
public struct MCPInboundFrame: Sendable {
    /// The decoded messages of one wire frame.
    public let messages: [JSONRPCMessage]

    /// Runs `operation` inside this frame's outbound scope.
    public let within: @Sendable (_ operation: @Sendable () async -> Void) async -> Void

    /// Creates a frame with an explicit outbound scope.
    public init(
        _ messages: [JSONRPCMessage],
        within: @escaping @Sendable (_ operation: @Sendable () async -> Void) async -> Void
    ) {
        self.messages = messages
        self.within = within
    }

    /// Creates a frame with a pass-through scope (a one-socket transport whose
    /// outbound has a single destination).
    public init(_ messages: [JSONRPCMessage]) {
        self.init(messages, within: { await $0() })
    }
}
