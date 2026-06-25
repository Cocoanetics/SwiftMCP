//
//  MCPTransport.swift
//  SwiftMCP
//
//  The connection-based transport boundary. Gated behind the `Server` trait
//  because it refines swift-service-lifecycle's `Service`.
//

#if Server
import ServiceLifecycle

/// A source of JSON-RPC connections, decoupled from the MCP server.
///
/// An ``MCPTransport`` owns the wire specifics — stdio framing, a TCP listener
/// with Bonjour advertising, HTTP POST + SSE — and surfaces each client as an
/// ``MCPConnection``. It does **not** hold a reference to the server and never
/// dispatches MCP messages itself; that is the job of
/// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``, which consumes
/// ``connections`` and routes each frame.
///
/// Conformance to `Service` (from
/// [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle))
/// means a transport participates in graceful startup and shutdown. `serve`
/// builds the `ServiceGroup` for you with the correct ordering and
/// failure-handling, so consumers no longer hand-wire one.
///
/// ## Implementing a transport
///
/// 1. Accept connections however the wire dictates, wrapping each as an
///    ``MCPConnection`` whose ``MCPConnection/inbound`` yields decoded frames and
///    whose `send(_:)` writes them back.
/// 2. Yield each new connection to ``connections``.
/// 3. Run until graceful shutdown in `Service.run()`; finish the ``connections``
///    stream (and each connection's `inbound`) on stop so routing unwinds.
///
/// Because the transport is server-agnostic, it can be unit-tested by draining
/// ``connections`` and driving a connection directly.
public protocol MCPTransport: Service {
    /// The stream of client connections accepted by this transport.
    ///
    /// Each element is a freshly accepted ``MCPConnection``. The stream finishes
    /// when the transport stops accepting connections (for example, after a
    /// graceful shutdown), which lets `serve(over:)` stop routing for this
    /// transport.
    var connections: AsyncStream<MCPConnection> { get }
}
#endif
