#if Client
import Foundation

/// Bridges a SwiftMCP line-based ``StdioConnection`` (newline-delimited JSON over
/// TCP or in-process pipes) onto JSONFoundation's shared ``JSONRPCMessageTransport``
/// seam, so the client's TCP and in-process connections can be driven by the same
/// ``JSONRPCPeer`` correlator as the spawned-stdio transport.
///
/// The spawned-stdio case uses JSONFoundation's `StdioMessageTransport` directly;
/// this adapter exists only for the transports JSONFoundation does not ship — TCP
/// (Network framework) and the in-process server bridge — letting them all share
/// the one correlation/dispatch runtime.
///
/// Outbound `send` is synchronous (the sink contract) but the wrapped connection's
/// `write` is `async`, so messages are enqueued to an ordered stream drained by a
/// single writer task — mirroring how `StdioMessageTransport` decouples its sync
/// `send` from its async I/O.
final class LineConnectionTransport: JSONRPCMessageTransport, @unchecked Sendable {
    private let connection: any StdioConnection
    private let outbound: AsyncStream<JSONRPCMessage>.Continuation
    private let writerTask: Task<Void, Never>
    /// Newline framing for the outbound half — the shared `JSONRPCWire` codec, the
    /// one axis SwiftMCP's line transports share with LSP/ACP over stdio.
    private let framing = LineFraming()

    init(connection: any StdioConnection) {
        self.connection = connection
        let (stream, continuation) = AsyncStream<JSONRPCMessage>.makeStream()
        self.outbound = continuation
        let framing = self.framing
        self.writerTask = Task {
            for await message in stream {
                guard let body = try? message.encoded() else { continue }
                await connection.write(framing.frame(body))
            }
        }
    }

    func send(_ message: JSONRPCMessage) throws {
        guard case .enqueued = outbound.yield(message) else {
            throw JSONRPCPeerError.closed
        }
    }

    func makeInboundStream() -> AsyncThrowingStream<JSONRPCMessage, Error> {
        let connection = self.connection
        return AsyncThrowingStream { continuation in
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
