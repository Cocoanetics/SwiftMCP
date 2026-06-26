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
///
/// `StdioTransport` works in two modes:
///
/// - **Server-coupled (legacy):** construct it with `init(server:)` and run it
///   directly (e.g. inside your own `ServiceGroup`). It reads stdin, dispatches
///   through the server, and writes responses to stdout itself.
/// - **Decoupled:** construct it with `init()` (no server) and hand it to
///   ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``, which connects an
///   ``MCPDispatcher`` via ``connect(to:)``. It then reads stdin, calls
///   ``MCPDispatcher/handle(_:)-(JSONRPCMessage)``, and writes the reply.
public final class StdioTransport: Transport, MCPTransport, Service, @unchecked Sendable {
    /// The MCP server instance that this transport exposes, when used in the
    /// server-coupled mode. `nil` in the decoupled mode, where the
    /// ``MCPDispatcher`` connected by
    /// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` owns dispatch.
    public let server: MCPServer?

    /// The dispatcher `serve` connects in the decoupled mode. `nil` until
    /// ``connect(to:)`` is called (and in the server-coupled mode).
    private var dispatcher: (any MCPDispatcher)?

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

    /// Initializes a server-coupled StdioTransport with the given MCP server.
    ///
    /// - Parameter server: The MCP server to expose over standard input/output.
    public init(server: MCPServer) {
        self.server = server
    }

    /// Initializes a decoupled StdioTransport with no server.
    ///
    /// Pass the transport to ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``,
    /// which connects an ``MCPDispatcher`` and runs it.
    public init() {
        self.server = nil
    }

    /// Connects the dispatcher `serve` routes inbound stdin payloads through.
    public func connect(to dispatcher: any MCPDispatcher) {
        self.dispatcher = dispatcher
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
                if server != nil {
                    try await readLoop()
                } else {
                    try await serveReadLoop()
                }
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
    /// In the decoupled mode (no `server`), stdin payloads are routed through the
    /// ``MCPDispatcher`` connected by
    /// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``.
    ///
    /// - Throws: An error if the transport fails to process input.
    public func run() async throws {
        await state.start()

        // A `ServiceGroup` graceful shutdown signal calls `stop()`, clearing the
        // running flag so the read loop exits; the loop also returns on stdin
        // EOF. Standalone callers drive shutdown via `stop()`.
        try await withGracefulShutdownHandler {
            if server != nil {
                try await readLoop()
            } else {
                try await serveReadLoop()
            }
        } onGracefulShutdown: { [weak self] in
            Task { [weak self] in try? await self?.stop() }
        }
    }

    /// Reads newline-delimited JSON-RPC messages from stdin until stdin reaches
    /// end-of-file or the transport is stopped (server-coupled mode).
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

    /// Decoupled read loop: binds one session, reads stdin **in order**, and
    /// routes each payload through the connected ``MCPDispatcher``, writing the
    /// reply to stdout. Wire framing and decoding stay here; the gate and dispatch
    /// are the dispatcher's job.
    ///
    /// Dispatch is in-order — a payload is fully handled before the next line is
    /// read — so a client that pipes `initialize` and a follow-up together (a
    /// scripted stdin) is never raced. (A tool that blocks on a server→client
    /// round-trip therefore stalls a single stdio peer until it completes, exactly
    /// as the server-coupled loop does.)
    private func serveReadLoop() async throws {
        let session = Session(id: UUID())
        await session.setTransport(self)
        await session.work { _ in
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
                await dispatchInbound(data)
            }
        }
        await state.stop()
    }

    /// Decodes one stdin payload and routes it through the dispatcher, writing any
    /// reply to stdout.
    private func dispatchInbound(_ data: Data) async {
        guard let dispatcher else {
            logger.error("Received stdio data before a dispatcher was connected")
            return
        }
        do {
            let messages = try JSONRPCMessage.decodeMessages(from: data)
            let replies: [JSONRPCMessage]
            if messages.count == 1 {
                if let reply = await dispatcher.handle(messages[0]) {
                    replies = [reply]
                } else {
                    replies = []
                }
            } else {
                replies = await dispatcher.handle(messages)
            }
            guard !replies.isEmpty else { return }
            try await send(replies)
        } catch {
            logger.error("Error handling stdio message: \(error)")
        }
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

    /// handle received data (server-coupled mode)
    func handleReceived(_ data: Data) async throws {
        guard let server else {
            logger.error("Received stdio data without a server (decoupled mode)")
            return
        }
        do {
            guard let session = Session.current else {
                logger.error("Received stdio data without an active session")
                return
            }

            let messages = try JSONRPCMessage.decodeMessages(from: data)

            if await SessionInitializationGate.shouldReject(messages, for: session) {
                logger.warning("Rejected stdio request before initialize")
                let rejections = SessionInitializationGate.rejectionResponses(for: messages)
                if !rejections.isEmpty {
                    try await send(rejections)
                }
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
