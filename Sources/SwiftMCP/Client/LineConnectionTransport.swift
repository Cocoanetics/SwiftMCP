#if Client
import Foundation

/// Bridges a SwiftMCP line-based ``StdioConnection`` (newline-delimited JSON over
/// TCP or in-process pipes) onto JSONFoundation's shared ``JSONRPCMessageTransport``
/// seam, so the client's TCP and in-process connections can be driven by the same
/// ``JSONRPCPeer`` correlator as the spawned-stdio transport.
///
/// The spawned-stdio case uses JSONFoundation's `StdioTransport` directly;
/// this adapter exists only for the transports JSONFoundation does not ship — TCP
/// (Network framework) and the in-process server bridge — letting them all share
/// the one correlation/dispatch runtime.
///
/// Outbound `send` is synchronous (the sink contract) but the wrapped connection's
/// `write` is `async`, so messages are enqueued to an ordered stream drained by a
/// single writer task — mirroring how `StdioTransport` decouples its sync
/// `send` from its async I/O.
final class LineConnectionTransport: JSONRPCMessageTransport, @unchecked Sendable {
    private let connection: any StdioConnection
    private let outbound: AsyncStream<JSONRPCMessage>.Continuation
    private var writerTask: Task<Void, Never>!
    /// Newline framing for the outbound half — the shared `JSONRPCWire` codec, the
    /// one axis SwiftMCP's line transports share with LSP/ACP over stdio.
    private let framing = LineFraming()

    init(connection: any StdioConnection) {
        self.connection = connection
        let (stream, continuation) = AsyncStream<JSONRPCMessage>.makeStream()
        self.outbound = continuation
        let framing = self.framing
        self.writerTask = Task { [weak self] in
            for await message in stream {
                guard let body = try? message.encoded() else { continue }
                do {
                    try await connection.write(framing.frame(body))
                } catch {
                    // A failed write means the link is unusable; fail the inbound side
                    // so pending requests are resolved with the error instead of hanging.
                    self?.failInbound(error)
                    return
                }
            }
        }
    }

    private let inboundLock = NSLock()
    private var inboundContinuation: AsyncThrowingStream<JSONRPCMessage, Error>.Continuation?
    private var writeError: Error?

    private func failInbound(_ error: Error) {
        inboundLock.lock()
        writeError = error
        let continuation = inboundContinuation
        inboundLock.unlock()
        continuation?.finish(throwing: error)
        outbound.finish()
        let connection = self.connection
        Task { await connection.stop() }
    }

    func send(_ message: JSONRPCMessage) throws {
        guard case .enqueued = outbound.yield(message) else {
            throw JSONRPCPeerError.closed
        }
    }

    func makeInboundStream() -> AsyncThrowingStream<JSONRPCMessage, Error> {
        let connection = self.connection
        return AsyncThrowingStream { continuation in
            inboundLock.lock()
            inboundContinuation = continuation
            let pendingError = writeError
            inboundLock.unlock()
            if let pendingError {
                continuation.finish(throwing: pendingError)
                return
            }
            Task {
                do {
                    // The connection already de-frames its byte stream into whole
                    // newline-delimited lines; decode each into a message.
                    for try await line in await connection.lines() {
                        guard let data = line.data(using: .utf8), !data.isEmpty else { continue }
                        for message in (try? JSONRPCMessage.decodeMessages(from: data)) ?? [] {
                            continuation.yield(message)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func close() {
        outbound.finish()
        writerTask.cancel()
        let connection = self.connection
        Task { await connection.stop() }
    }
}
#endif
