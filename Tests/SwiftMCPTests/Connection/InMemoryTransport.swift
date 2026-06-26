#if Server
import Foundation
import Logging
import ServiceLifecycle
@testable import SwiftMCP

/// Records an ordered timeline of lifecycle events, shared between a transport
/// and a server so tests can assert *who stopped before whom*.
actor EventLog {
    private(set) var events: [String] = []

    func record(_ event: String) {
        events.append(event)
    }
}

/// Captures a session's server→client outbound (responses, notifications,
/// `sampling`/`roots` requests) into the transport's `outbound` stream. `Session`
/// holds its transport weakly, so the owning ``InMemoryTransport`` retains this.
private final class InMemoryOutbound: Transport, @unchecked Sendable {
    let logger = Logger(label: "test.inmemory.outbound")
    private let yield: @Sendable ([JSONRPCMessage]) -> Void

    init(yield: @escaping @Sendable ([JSONRPCMessage]) -> Void) {
        self.yield = yield
    }

    func start() async throws {}
    func run() async throws {}
    func stop() async throws {}

    func send(_ data: Data) async throws {
        yield(try JSONRPCMessage.decodeMessages(from: data))
    }
}

/// An in-memory ``MCPTransport`` for tests. It owns one client session, routes
/// each ``clientSends(_:)`` frame through the connected ``MCPDispatcher``, and
/// surfaces the server's outbound (replies, notifications, and server→client
/// requests) on ``outbound``.
///
/// Two dispatch disciplines, mirroring the bundled transports:
///
/// - **ordered** (default): frames dispatch in order on `run()`'s loop — like
///   stdio, a payload is fully handled before the next, so a piped
///   `initialize`+follow-up is never raced.
/// - **concurrent**: each `clientSends` dispatches on its own task — like HTTP's
///   per-request handling, so a tool can make a server→client round-trip mid-call.
final class InMemoryTransport: MCPTransport, @unchecked Sendable {
    let session = Session(id: UUID())

    private var dispatcher: (any MCPDispatcher)?
    private let concurrent: Bool

    /// Frames the server sent to the client, in order.
    let outbound: AsyncStream<[JSONRPCMessage]>
    private let outboundContinuation: AsyncStream<[JSONRPCMessage]>.Continuation

    /// Client→server frames awaiting in-order dispatch (ordered mode only).
    private let inbound: AsyncStream<[JSONRPCMessage]>
    private let inboundContinuation: AsyncStream<[JSONRPCMessage]>.Continuation

    private let outboundShim: InMemoryOutbound

    private let label: String
    private let eventLog: EventLog?
    private let runError: Error?

    init(
        label: String = "memory",
        eventLog: EventLog? = nil,
        runError: Error? = nil,
        concurrent: Bool = false
    ) {
        self.label = label
        self.eventLog = eventLog
        self.runError = runError
        self.concurrent = concurrent

        var outCont: AsyncStream<[JSONRPCMessage]>.Continuation!
        outbound = AsyncStream { outCont = $0 }
        outboundContinuation = outCont

        var inCont: AsyncStream<[JSONRPCMessage]>.Continuation!
        inbound = AsyncStream { inCont = $0 }
        inboundContinuation = inCont

        let yield = outCont!
        outboundShim = InMemoryOutbound { messages in yield.yield(messages) }
    }

    func connect(to dispatcher: any MCPDispatcher) {
        self.dispatcher = dispatcher
    }

    /// The client handle to drive. A transport owns one client session in these
    /// tests, so this is the transport itself.
    @discardableResult
    func accept() -> InMemoryTransport { self }

    /// Simulates the client sending a JSON-RPC frame (one message, or a batch).
    func clientSends(_ frame: [JSONRPCMessage]) {
        if concurrent {
            Task { await dispatch(frame) }
        } else {
            inboundContinuation.yield(frame)
        }
    }

    /// Simulates the client disconnecting; ends the in-order queue.
    func clientDisconnects() {
        inboundContinuation.finish()
    }

    /// Ends `run()` as if the transport finished serving.
    func stop() {
        inboundContinuation.finish()
    }

    func run() async throws {
        if let runError {
            await Task.yield()
            outboundContinuation.finish()
            throw runError
        }

        await withGracefulShutdownHandler {
            // Ordered mode drains this queue in order; concurrent mode never
            // enqueues (it dispatches on its own tasks), so this just parks until
            // `stop()` finishes the stream.
            for await frame in inbound {
                await dispatch(frame)
            }
        } onGracefulShutdown: {
            self.stop()
        }

        outboundContinuation.finish()
        await eventLog?.record("\(label) stopped")
    }

    /// Binds the session (so the server's outbound routes back here) and routes
    /// the frame through the dispatcher, surfacing any reply on ``outbound``.
    private func dispatch(_ frame: [JSONRPCMessage]) async {
        guard let dispatcher else { return }
        await session.setTransport(outboundShim)
        await session.work { _ in
            let replies: [JSONRPCMessage]
            if frame.count == 1 {
                if let reply = await dispatcher.handle(frame[0]) {
                    replies = [reply]
                } else {
                    replies = []
                }
            } else {
                replies = await dispatcher.handle(frame)
            }
            if !replies.isEmpty {
                self.outboundContinuation.yield(replies)
            }
        }
    }
}
#endif
