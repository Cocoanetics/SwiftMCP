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

/// An in-memory single-message ``MCPConnection`` for tests: inject inbound
/// messages as if from a client, and observe whatever the server sends back. No
/// sockets, no server reference.
final class InMemoryConnection: MCPConnection, @unchecked Sendable {
    let inbound: AsyncStream<JSONRPCMessage>
    private let inboundContinuation: AsyncStream<JSONRPCMessage>.Continuation

    /// Messages the server sent to the client, in order.
    let outbound: AsyncStream<JSONRPCMessage>
    private let outboundContinuation: AsyncStream<JSONRPCMessage>.Continuation

    init() {
        var inCont: AsyncStream<JSONRPCMessage>.Continuation!
        inbound = AsyncStream { inCont = $0 }
        inboundContinuation = inCont

        var outCont: AsyncStream<JSONRPCMessage>.Continuation!
        outbound = AsyncStream { outCont = $0 }
        outboundContinuation = outCont
    }

    func send(_ message: JSONRPCMessage) async throws {
        outboundContinuation.yield(message)
    }

    /// Simulates the client sending a JSON-RPC message to the server.
    func clientSends(_ message: JSONRPCMessage) {
        inboundContinuation.yield(message)
    }

    /// Simulates the client disconnecting; ends the inbound stream.
    func clientDisconnects() {
        inboundContinuation.finish()
        outboundContinuation.finish()
    }
}

/// An in-memory batch-capable ``MCPBatchConnection`` for tests: inject inbound
/// frames (including multi-message batches) and observe outbound frames.
final class InMemoryBatchConnection: MCPBatchConnection, @unchecked Sendable {
    let inboundBatches: AsyncStream<[JSONRPCMessage]>
    private let inboundContinuation: AsyncStream<[JSONRPCMessage]>.Continuation

    /// Frames the server sent to the client, in order.
    let outboundFrames: AsyncStream<[JSONRPCMessage]>
    private let outboundContinuation: AsyncStream<[JSONRPCMessage]>.Continuation

    init() {
        var inCont: AsyncStream<[JSONRPCMessage]>.Continuation!
        inboundBatches = AsyncStream { inCont = $0 }
        inboundContinuation = inCont

        var outCont: AsyncStream<[JSONRPCMessage]>.Continuation!
        outboundFrames = AsyncStream { outCont = $0 }
        outboundContinuation = outCont
    }

    func send(_ batch: [JSONRPCMessage]) async throws {
        outboundContinuation.yield(batch)
    }

    /// Simulates the client sending a JSON-RPC frame (one message, or a batch).
    func clientSends(_ frame: [JSONRPCMessage]) {
        inboundContinuation.yield(frame)
    }

    func clientDisconnects() {
        inboundContinuation.finish()
        outboundContinuation.finish()
    }
}

/// An in-memory ``MCPTransport`` for tests. Connections are pushed in by the
/// test via ``accept()`` / ``acceptBatch()``; `run()` blocks until ``stop()``
/// (or graceful shutdown), then finishes the connections stream. Optionally
/// fails its `run()` to exercise the failure-termination path.
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

    /// Makes a fresh single-message connection appear to the server.
    @discardableResult
    func accept() -> InMemoryConnection {
        let connection = InMemoryConnection()
        connectionsContinuation.yield(connection)
        return connection
    }

    /// Makes a fresh batch-capable connection appear to the server.
    @discardableResult
    func acceptBatch() -> InMemoryBatchConnection {
        let connection = InMemoryBatchConnection()
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
            // Surface a transport failure once the group is up.
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
