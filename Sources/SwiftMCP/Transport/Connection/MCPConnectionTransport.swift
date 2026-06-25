//
//  MCPConnectionTransport.swift
//  SwiftMCP
//
//  Internal glue: lets a connection-backed `Session` push outbound bytes
//  through an `MCPConnection`. Gated behind `Server` alongside the rest of the
//  connection-based serving stack.
//

#if Server
import Foundation
import Logging

/// A minimal ``Transport`` adapter that forwards a ``Session``'s outbound bytes
/// to an ``MCPConnection``.
///
/// ``Session`` writes every server→client message (responses, progress and log
/// notifications, `sampling`/`roots` requests) through its weakly-held
/// ``Transport``. When ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``
/// routes a connection it binds one of these as the session's transport, so all
/// of the server's existing outbound paths flow over the connection unchanged —
/// no modification to ``Session`` or the request handlers required.
///
/// The adapter only implements outbound (`send`); inbound is driven by the
/// connection's ``MCPConnection/inbound`` stream, and the run-loop/lifecycle is
/// owned by the real ``MCPTransport``. Its lifecycle methods are therefore
/// no-ops.
final class MCPConnectionTransport: Transport, @unchecked Sendable {
    /// The connection outbound bytes are forwarded to.
    let connection: any MCPConnection

    /// Logger inherited from `serve(over:)`.
    let logger: Logger

    init(connection: any MCPConnection, logger: Logger) {
        self.connection = connection
        self.logger = logger
    }

    func start() async throws {}
    func run() async throws {}
    func stop() async throws {}

    /// Decodes the JSON-RPC payload `Session` produced and forwards it on the
    /// connection.
    ///
    /// `Session` always hands us a single encoded message (responses,
    /// notifications, `sampling`/`roots` requests), so we decode and forward it
    /// via the single-message ``MCPConnection/send(_:)``. A batch connection turns
    /// that into a one-element frame.
    func send(_ data: Data) async throws {
        let messages = try JSONRPCMessage.decodeMessages(from: data)
        for message in messages {
            try await connection.send(message)
        }
    }
}
#endif
