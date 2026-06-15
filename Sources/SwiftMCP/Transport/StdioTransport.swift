#if Server
#if canImport(Glibc)
@preconcurrency import Glibc
#endif

import Foundation
import Logging
import ServiceLifecycle

/// A transport that exposes an MCP server over standard input/output.
///
/// This transport allows communication with an MCP server through standard input and output streams,
/// making it suitable for command-line interfaces and pipe-based communication.
public final class StdioTransport: Transport, Service, @unchecked Sendable {
    /// The MCP server instance that this transport exposes.
    ///
    /// This server handles the actual business logic while the transport handles I/O.
    public let server: MCPServer

    /// Logger instance for logging transport activity.
    ///
    /// Used to track input/output operations and error conditions during transport operation.
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.StdioTransport")

    /// Actor to handle running state in a thread-safe manner.
    private actor TransportState {
        var isRunning: Bool = false

        func start() {
            isRunning = true
        }

        func stop() {
            isRunning = false
        }

        func isCurrentlyRunning() -> Bool {
            return isRunning
        }
    }

    private let state = TransportState()

    /// Initializes a new StdioTransport with the given MCP server.
    ///
    /// - Parameter server: The MCP server to expose over standard input/output.
    public init(server: MCPServer) {
        self.server = server
    }

    /// Starts reading from stdin asynchronously in a non-blocking manner.
    ///
    /// This method initiates a background task that processes input continuously until stopped.
    /// The background task reads JSON-RPC messages from stdin and forwards them to the MCP server.
    ///
    /// - Throws: An error if the transport fails to start or process input.
    public func start() async throws {
        await state.start()

        // Read on a background task so this method returns immediately.
        Task { @Sendable in
            do {
                try await readLoop()
            } catch {
                logger.error("Error processing input: \(error)")
            }
        }
    }

    /// Runs the transport, processing stdin on the calling task until the
    /// transport is stopped or stdin reaches end-of-file.
    ///
    /// Returns when `stop()` is called from another task, when a `ServiceGroup`
    /// graceful shutdown is triggered, or when the peer closes stdin (EOF).
    ///
    /// - Throws: An error if the transport fails to process input.
    public func run() async throws {
        await state.start()

        // A `ServiceGroup` graceful shutdown signal calls `stop()`, clearing the
        // running flag so the read loop exits; the loop also returns on stdin
        // EOF. Standalone callers drive shutdown via `stop()`.
        try await withGracefulShutdownHandler {
            try await readLoop()
        } onGracefulShutdown: { [weak self] in
            Task { [weak self] in try? await self?.stop() }
        }
    }

    /// Reads newline-delimited JSON-RPC messages from stdin until stdin reaches
    /// end-of-file or the transport is stopped.
    ///
    /// `readLine()` blocks until a complete line or EOF is available, so the loop
    /// needs no polling delay. A `nil` result means the peer closed stdin (EOF),
    /// in which case the loop returns so the caller can shut down cleanly. Blank
    /// or non-UTF8 lines are skipped.
    private func readLoop() async throws {
        let session = Session(id: UUID())
        await session.setTransport(self)
        try await session.work { _ in
            while await state.isCurrentlyRunning() {
                guard let input = readLine() else {
                    // EOF: stdin was closed by the peer.
                    break
                }
                guard !input.isEmpty, let data = input.data(using: .utf8) else {
                    // Blank or non-UTF8 line — skip and keep reading.
                    continue
                }
                logger.trace("STDIN:\n\n\(input)")
                try await handleReceived(data)
            }
        }
        // The read loop ended (EOF or an explicit stop); ensure the running flag
        // is cleared so the transport's state stays consistent.
        await state.stop()
    }

    /// Stops the transport.
    ///
    /// This method stops processing input from stdin. Any pending input will be discarded.
    ///
    /// - Throws: An error if the transport fails to stop cleanly.
    public func stop() async throws {
        await state.stop()
    }

    // MARK: - Receiving

    /// handle received data
    func handleReceived(_ data: Data) async throws {
        do {
            guard let session = Session.current else {
                logger.error("Received stdio data without an active session")
                return
            }

            let messages = try JSONRPCMessage.decodeMessages(from: data)

            if await SessionInitializationGate.shouldReject(messages, for: session) {
                logger.warning("Rejected stdio request before initialize")
                try await send(SessionInitializationGate.rejectionResponses(for: messages))
                return
            }

            let batchVersion = await JSONRPCMessage.batchingVersion(for: messages, session: session)
            if JSONRPCMessage.batchingRejected(body: data, version: batchVersion) {
                logger.warning("Rejected stdio batch on protocol version \(batchVersion)")
                try await send([JSONRPCMessage.batchingRejectionResponse(version: batchVersion)])
                return
            }

            let responses = await server.processBatch(messages)

            guard !responses.isEmpty else {
                return
            }

            try await send(responses)

        } catch {
            logger.error("Error decoding message: \(error)")
        }
    }

    // MARK: - Sending

    /// send data to the client, specific to JSON
    public func send(_ data: Data) async throws {
        precondition(Session.current != nil)
        let currentSession = Session.current!
        let sameTransport: Bool
        if let transport = await currentSession.transport {
            sameTransport = transport === self
        } else {
            sameTransport = false
        }
        precondition(sameTransport)

        let string = String(data: data, encoding: .utf8)!
        logger.trace("STDOUT:\n\n\(string)")

        var out = data
        out.append(Data("\n".utf8))

        try FileHandle.standardOutput.write(contentsOf: out)
    }
}
#endif
