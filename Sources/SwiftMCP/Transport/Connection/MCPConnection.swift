//
//  MCPConnection.swift
//  SwiftMCP
//
//  The JSON-RPC duplex at the transport ↔ server boundary. See the
//  <doc:Connection-Based-Transports> article for the full picture.
//

import Foundation

/// A single, full-duplex JSON-RPC channel to one client.
///
/// A ``MCPTransport`` is a *source* of connections; each connection is one
/// JSON-RPC conversation. The connection knows nothing about the MCP server —
/// it only moves JSON-RPC messages in and out.
/// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` is the bridge that
/// pulls each connection's ``inbound`` messages, routes them through the server,
/// and writes replies back with `send(_:)`.
///
/// The base protocol deals in **single messages** — the common case, and the
/// only shape MCP `2025-06-18` and later use (that revision removed JSON-RPC
/// batching). A transport that needs to carry batches conforms to
/// ``MCPBatchConnection`` instead, which adds a whole-frame interface.
///
/// ## Testability
///
/// Because a connection is just two JSON-RPC streams, it can be exercised
/// without any networking: feed a canned ``inbound`` stream and assert on what
/// `send(_:)` receives. No server, sockets, or `ServiceGroup` required.
public protocol MCPConnection: Sendable {
    /// JSON-RPC messages arriving from the client.
    ///
    /// The stream finishes when the client disconnects or the underlying
    /// transport stops, which lets the per-connection routing loop in
    /// `serve(over:)` end cleanly.
    var inbound: AsyncStream<JSONRPCMessage> { get }

    /// Sends a JSON-RPC message to the client.
    ///
    /// Server→client pushes — responses, progress and log notifications emitted
    /// mid–tool-call, or `sampling`/`elicitation`/`roots` requests — all travel
    /// through this method.
    ///
    /// - Parameter message: The message to deliver.
    /// - Throws: A transport-specific error if the message cannot be written
    ///   (for example, the connection has already closed).
    func send(_ message: JSONRPCMessage) async throws
}

/// A connection that can also carry JSON-RPC *batches* — a top-level array of
/// messages that must round-trip as one wire payload.
///
/// Batching was removed in MCP `2025-06-18`, so this is an opt-in refinement for
/// transports that still need to interoperate with older clients. A batch-capable
/// transport (stdio, TCP) conforms to `MCPBatchConnection`;
/// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` then routes whole
/// frames through ``MCPServer/processBatch(_:ignoringEmptyResponses:)`` (and
/// applies the version-gated batch reject), instead of the per-message path it
/// uses for a plain ``MCPConnection``.
///
/// Conformers implement only the batch members; the single-message
/// ``MCPConnection`` requirements are derived for free (a message is sent as a
/// one-element frame, and ``MCPConnection/inbound`` flattens
/// ``inboundBatches``).
public protocol MCPBatchConnection: MCPConnection {
    /// Inbound JSON-RPC frames. A single message arrives as a one-element frame;
    /// a JSON-RPC batch arrives as a multi-element frame.
    var inboundBatches: AsyncStream<[JSONRPCMessage]> { get }

    /// Sends a whole JSON-RPC frame as one wire payload, preserving batch
    /// semantics.
    /// - Parameter batch: One or more JSON-RPC messages to deliver together.
    /// - Throws: A transport-specific error if the frame cannot be written.
    func send(_ batch: [JSONRPCMessage]) async throws
}

public extension MCPBatchConnection {
    /// Derives the single-message inbound stream by flattening ``inboundBatches``.
    /// `serve` consumes ``inboundBatches`` directly for batch connections, so
    /// this exists only to satisfy ``MCPConnection`` conformance.
    var inbound: AsyncStream<JSONRPCMessage> {
        let batches = inboundBatches
        return AsyncStream { continuation in
            let task = Task {
                for await frame in batches {
                    for message in frame {
                        continuation.yield(message)
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Sends a single message as a one-element frame.
    func send(_ message: JSONRPCMessage) async throws {
        try await send([message])
    }
}
