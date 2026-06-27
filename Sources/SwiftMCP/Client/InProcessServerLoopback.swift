#if Client
import Foundation

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
    private var task: Task<Void, Never>?

    init(server: any MCPServer & Sendable) {
        let pair = LoopbackTransport.pair()
        self.clientTransport = pair.client
        self.serverTransport = pair.server
        self.server = server
    }

    /// Begins reading the server end and dispatching messages. Call once, before
    /// driving the client end.
    func start() {
        let serverTransport = self.serverTransport
        let server = self.server
        let session = self.session
        task = Task {
            do {
                for try await message in serverTransport.makeInboundStream() {
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
#endif
