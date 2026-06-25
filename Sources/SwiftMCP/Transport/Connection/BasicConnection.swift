//
//  BasicConnection.swift
//  SwiftMCP
//
//  The one-socket connection shape: a fresh session whose outbound is wired back
//  to the transport. Gated behind `Server` alongside the rest of the serving
//  stack.
//

#if Server
import Foundation

/// A ready-made ``MCPConnection`` for a transport that is a single duplex (stdio,
/// TCP, an in-memory pipe).
///
/// It owns a fresh ``Session`` and exposes a plain `inbound` stream; `serve`
/// wires the session's outbound back through this connection's `send`. The
/// transport only has to feed decoded frames with ``deliver(_:)`` / ``close()``
/// and supply the byte-level `send` sink — it never touches `Session`,
/// `Session.current`, or stream routing.
///
/// ```swift
/// let connection = BasicConnection { frame in
///     try await writeLine(JSONRPCFrame.encode(frame))   // the wire
/// }
/// transport.accept(connection)
/// for line in lines { connection.deliver(try decode(line)) }
/// connection.close()   // on EOF
/// ```
public final class BasicConnection: MCPConnection, @unchecked Sendable {
    public let session: Session
    public let inbound: AsyncStream<MCPInboundFrame>

    private let inboundContinuation: AsyncStream<MCPInboundFrame>.Continuation
    private let sink: @Sendable ([JSONRPCMessage]) async throws -> Void

    /// Creates a connection with a fresh session.
    /// - Parameter send: Writes an outbound JSON-RPC frame to the wire.
    public init(send: @escaping @Sendable ([JSONRPCMessage]) async throws -> Void) {
        self.session = Session(id: UUID())
        self.sink = send
        var continuation: AsyncStream<MCPInboundFrame>.Continuation!
        inbound = AsyncStream { continuation = $0 }
        inboundContinuation = continuation
    }

    /// Hands `serve` a decoded inbound frame to dispatch.
    public func deliver(_ messages: [JSONRPCMessage]) {
        inboundContinuation.yield(MCPInboundFrame(messages))
    }

    /// Ends the inbound stream (client disconnect / transport stop).
    public func close() {
        inboundContinuation.finish()
    }

    public func send(_ frame: [JSONRPCMessage]) async throws {
        try await sink(frame)
    }
}
#endif
