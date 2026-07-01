//
//  MCPDispatcher.swift
//  SwiftMCP
//
//  The server-side dispatch surface a transport calls. See the
//  <doc:Decoupled-Transports> article for the full picture.
//

#if Server
import Foundation

/// The dispatch surface a transport calls for each inbound payload.
///
/// A ``MCPTransport`` owns its wire, its sessions, and its outbound `send`. For
/// every decoded payload it binds the owning ``Session`` as `Session.current`
/// (plus, where it has one, the outbound stream scope) and calls ``handle(_:)``
/// — for a single message or a whole batch — then writes back whatever it
/// returns.
///
/// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` hands each transport
/// the dispatcher (via ``MCPTransport/connect(to:)``) and owns nothing else of the
/// run loop. The init/batch **gate** lives behind `handle` — against
/// `Session.current` — so a transport never reimplements "reject before
/// initialize" or "reject a batch on a no-batching revision."
public protocol MCPDispatcher: Sendable {
    /// Dispatches a single inbound message, returning its reply — or `nil` for a
    /// notification, an accepted request, or a gated-away message.
    func handle(_ message: JSONRPCMessage) async -> JSONRPCMessage?

    /// Dispatches an inbound JSON-RPC batch, returning the replies (possibly
    /// empty). A multi-message batch round-trips as one unit; batching was removed
    /// in MCP `2025-06-18`, so most callers send a single message via
    /// ``handle(_:)-(JSONRPCMessage)`` instead.
    func handle(_ batch: [JSONRPCMessage]) async -> [JSONRPCMessage]
}

/// The ``MCPDispatcher`` `serve` hands its transports.
///
/// It gates each payload against the bound `Session.current` — opening the
/// session on `initialize`, rejecting non-`initialize` requests before that, and
/// rejecting batches on protocol revisions that removed batching (`2025-06-18`+)
/// — then dispatches through the server. The gate runs in `handle`, so it is
/// applied wherever the transport calls in.
struct MCPServerDispatcher<Server: MCPServer & Sendable>: MCPDispatcher {
    let server: Server

    func handle(_ message: JSONRPCMessage) async -> JSONRPCMessage? {
        guard let session = Session.current else {
            return await server.handleMessage(message)
        }
        if let rejections = await gate([message], session: session) {
            return rejections.first
        }
        return await server.handleMessage(message)
    }

    func handle(_ batch: [JSONRPCMessage]) async -> [JSONRPCMessage] {
        guard let session = Session.current else {
            return await server.processBatch(batch)
        }
        if let rejections = await gate(batch, session: session) {
            return rejections
        }
        // Route every message (including empty client responses, so a tool
        // awaiting an empty-result reply resumes) — symmetric with `handle(message)`.
        return await server.processBatch(batch)
    }

    /// Applies the init/batch gate to a payload. Returns the responses to send
    /// back when the payload is rejected, or `nil` to proceed with dispatch.
    ///
    /// A payload beginning with `initialize` opens the session (marked here so a
    /// follow-up admitted afterwards isn't spuriously rejected). `server/discover`
    /// is also admitted before initialization (it is sessionless and does not open
    /// the session — see ``SessionInitializationGate/preInitializeMethods``); every
    /// other request before initialization, and batches on revisions that removed
    /// batching, are rejected.
    private func gate(_ messages: [JSONRPCMessage], session: Session) async -> [JSONRPCMessage]? {
        if SessionInitializationGate.batchStartsWithInitialize(messages) {
            await session.markInitializeRequestReceived()
            return nil
        }
        if await SessionInitializationGate.shouldReject(messages, for: session) {
            return SessionInitializationGate.rejectionResponses(for: messages)
        }
        let version = await JSONRPCMessage.batchingVersion(for: messages, session: session)
        if JSONRPCMessage.batchingRejected(frame: messages, version: version) {
            return [JSONRPCMessage.batchingRejectionResponse(version: version)]
        }
        return nil
    }
}
#endif
