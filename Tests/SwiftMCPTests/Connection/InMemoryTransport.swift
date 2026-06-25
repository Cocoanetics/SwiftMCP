#if Server
import Foundation
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

/// An in-memory ``MCPConnection`` for tests: inject inbound frames as if from a
/// client, and observe the frames the server sends back. Owns a fresh session,
/// like any one-socket connection.
final class InMemoryConnection: MCPConnection, @unchecked Sendable {
    let session = Session(id: UUID())

    let inbound: AsyncStream<MCPInboundFrame>
    private let inboundContinuation: AsyncStream<MCPInboundFrame>.Continuation

    /// Frames the server sent to the client, in order.
    let outbound: AsyncStream<[JSONRPCMessage]>
    private let outboundContinuation: AsyncStream<[JSONRPCMessage]>.Continuation

    init() {
        var inCont: AsyncStream<MCPInboundFrame>.Continuation!
        inbound = AsyncStream { inCont = $0 }
        inboundContinuation = inCont

        var outCont: AsyncStream<[JSONRPCMessage]>.Continuation!
        outbound = AsyncStream { outCont = $0 }
        outboundContinuation = outCont
    }

    func send(_ frame: [JSONRPCMessage]) async throws {
        outboundContinuation.yield(frame)
    }

    /// Simulates the client sending a JSON-RPC frame (one message, or a batch).
    func clientSends(_ frame: [JSONRPCMessage]) {
        inboundContinuation.yield(MCPInboundFrame(frame))
    }

    /// Simulates the client disconnecting; ends the inbound stream.
    func clientDisconnects() {
        inboundContinuation.finish()
        outboundContinuation.finish()
    }
}

/// An in-memory ``MCPTransport`` for tests. Connections are pushed in by the
/// test via ``accept()``; `run()` blocks until ``stop()`` (or graceful
/// shutdown), then finishes the connections stream. Optionally fails its `run()`
/// to exercise the failure-termination path.
final class InMemoryTransport: MCPTransport, @unchecked Sendable {
    let connections: AsyncStream<MCPConnection>
    private let connectionsContinuation: AsyncStream<MCPConnection>.Continuation

    private let stopStream: AsyncStream<Void>
    private let stopContinuation: AsyncStream<Void>.Continuation

    private let label: String
    private let eventLog: EventLog?
    private let runError: Error?

    init(label: String = "memory", eventLog: EventLog? = nil, runError: Error? = nil) {
        self.label = label
        self.eventLog = eventLog
        self.runError = runError

        var connCont: AsyncStream<MCPConnection>.Continuation!
        connections = AsyncStream { connCont = $0 }
        connectionsContinuation = connCont

        var stopCont: AsyncStream<Void>.Continuation!
        stopStream = AsyncStream { stopCont = $0 }
        stopContinuation = stopCont
    }

    /// Makes a fresh connection appear to the server and returns it for driving.
    @discardableResult
    func accept() -> InMemoryConnection {
        let connection = InMemoryConnection()
        connectionsContinuation.yield(connection)
        return connection
    }

    /// Ends `run()` as if the transport finished serving.
    func stop() {
        stopContinuation.yield(())
        stopContinuation.finish()
    }

    func run() async throws {
        if let runError {
            await Task.yield()
            connectionsContinuation.finish()
            throw runError
        }

        await withGracefulShutdownHandler {
            for await _ in stopStream { break }
        } onGracefulShutdown: {
            self.stop()
        }

        connectionsContinuation.finish()
        await eventLog?.record("\(label) stopped")
    }
}
#endif
