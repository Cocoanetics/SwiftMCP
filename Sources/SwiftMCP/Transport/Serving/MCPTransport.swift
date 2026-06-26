//
//  MCPTransport.swift
//  SwiftMCP
//
//  The transport boundary, decoupled from the MCP server. Gated behind the
//  `Server` trait because it refines swift-service-lifecycle's `Service`.
//

#if Server
import ServiceLifecycle

/// A transport that serves an MCP server without holding a reference to it.
///
/// An ``MCPTransport`` owns the wire specifics — stdio framing, a TCP listener
/// with Bonjour advertising, HTTP POST + SSE — and its own ``Session``s. It does
/// **not** know the server type. Instead,
/// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` hands it an
/// ``MCPDispatcher`` via ``connect(to:)``; for every decoded payload the transport
/// binds the owning session and calls ``MCPDispatcher/handle(_:)-(JSONRPCMessage)``
/// (a message) or ``MCPDispatcher/handle(_:)-([JSONRPCMessage])`` (a batch), then
/// writes back whatever it returns.
///
/// Conformance to `Service` (from
/// [swift-service-lifecycle](https://github.com/swift-server/swift-service-lifecycle))
/// means a transport participates in graceful startup and shutdown. `serve`
/// builds the `ServiceGroup` for you with the correct ordering and
/// failure-handling, so consumers no longer hand-wire one.
///
/// ## Implementing a transport
///
/// 1. Store the ``MCPDispatcher`` handed to ``connect(to:)``.
/// 2. In `Service.run()`, read the wire. For each decoded payload, bind the
///    owning session as `Session.current` (and any outbound stream scope), call
///    `handle`, and write the reply.
/// 3. Run until graceful shutdown; stop reading and release sessions on stop.
///
/// Because the transport never sees the server, it can be unit-tested by handing
/// it a stub ``MCPDispatcher`` and driving its wire directly.
public protocol MCPTransport: Service {
    /// Connects the transport to the dispatcher it should route inbound payloads
    /// through.
    ///
    /// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` calls this once,
    /// before the service group runs, so the dispatcher is in place by the time
    /// `run()` starts reading. The transport calls ``MCPDispatcher/handle(_:)-(JSONRPCMessage)``
    /// for each inbound payload thereafter.
    func connect(to dispatcher: any MCPDispatcher)
}
#endif
