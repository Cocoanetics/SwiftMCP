#if Client
import Foundation
import Logging

/// Runs an in-process ``MCPServer`` over JSONFoundation's ``LoopbackTransport``, so
/// the client's `.stdioHandles` path can talk to an embedded server with **no OS
/// pipes** — the client end is a plain ``JSONRPCMessageTransport`` driven by the
/// same ``JSONRPCPeer`` as the stdio/TCP transports.
///
/// The loopback hands whole messages across (no framing); this runner is the server
/// half — it reads each inbound message, applies the same init gate the wire
/// transports use, dispatches it through the server, and writes the replies back.
/// It mirrors the old pipe-based `InProcessStdioBridge` dispatch, minus the byte
/// plumbing.
final class InProcessServerLoopback: @unchecked Sendable {
    /// The client end of the pair — hand this to the proxy's ``JSONRPCPeer``.
    let clientTransport: LoopbackTransport
    private let serverTransport: LoopbackTransport
    private let server: any MCPServer & Sendable
    private let session = Session(id: UUID())
    /// The session's outbound transport. ``Session`` holds it weakly, so the
    /// loopback keeps it alive for as long as the pair runs.
    private let outbound: LoopbackSessionTransport
    private var task: Task<Void, Never>?

    init(server: any MCPServer & Sendable) {
        let pair = LoopbackTransport.pair()
        self.clientTransport = pair.client
        self.serverTransport = pair.server
        self.server = server
        self.outbound = LoopbackSessionTransport(serverTransport: pair.server)
    }

    /// Begins reading the server end and dispatching messages. Call once, before
    /// driving the client end.
    func start() {
        let serverTransport = self.serverTransport
        let server = self.server
        let session = self.session
        let outbound = self.outbound
        task = Task {
            // Attach the outbound transport first, so notifications and
            // server→client requests a captured `Session` sends outside a request
            // (`sendResourceUpdated`, list-changed, log, elicitation…) reach the
            // client instead of going to a nil transport.
            await session.setTransport(outbound)
            do {
                for try await message in serverTransport.makeInboundStream() {
                    // Each message gets its own task, like the pipe-based bridge's
                    // task-per-line dispatch: a handler that suspends mid-call (a
                    // long-running or deliberately deferred tool) must not stall
                    // the read loop, or every later request deadlocks behind it.
                    // `LoopbackTransport.send` is lock-protected, so replies from
                    // concurrent handlers are safe to write as they finish.
                    Task {
                        let replies = await session.work { _ -> [JSONRPCMessage] in
                            // The in-process bridge is internal infrastructure, not an
                            // external wire, so it applies the init gate but is not
                            // version-gated for batching — matching the previous bridge.
                            if await SessionInitializationGate.shouldReject([message], for: session) {
                                return SessionInitializationGate.rejectionResponses(for: [message])
                            }
                            return await server.processBatch([message])
                        }
                        for reply in replies {
                            try? serverTransport.send(reply)
                        }
                    }
                }
            } catch {
                // Inbound stream ended (the client end closed) — nothing to do.
            }
        }
    }

    /// Stops the server loop and tears down both ends of the pair.
    func stop() {
        task?.cancel()
        serverTransport.close()
        clientTransport.close()
    }
}

/// The ``Transport`` a loopback ``Session`` writes outbound messages through:
/// it decodes the bytes ``Session`` hands it back into ``JSONRPCMessage``s and
/// sends them on the server end of the pair. There is nothing to start or stop —
/// the pair's lifetime belongs to ``InProcessServerLoopback``.
private final class LoopbackSessionTransport: Transport, @unchecked Sendable {
    let logger = Logger(label: "com.cocoanetics.SwiftMCP.InProcessServerLoopback")
    private let serverTransport: LoopbackTransport

    init(serverTransport: LoopbackTransport) {
        self.serverTransport = serverTransport
    }

    func start() async throws {}

    func run() async throws {}

    func stop() async throws {}

    func send(_ data: Data) async throws {
        for message in try JSONRPCMessage.decodeMessages(from: data) {
            try serverTransport.send(message)
        }
    }
}
#endif
