//
//  MCPServer+Serve.swift
//  SwiftMCP
//
//  `serve(over:)` — the bridge between connection-based transports and the
//  server — plus the `shutdown()` lifecycle hook. Gated behind `Server` because
//  it builds a swift-service-lifecycle `ServiceGroup`.
//

#if Server
import Foundation
import Logging
import ServiceLifecycle
import UnixSignals

public extension MCPServer {
    /// Serves this server over one or more connection-based transports, owning
    /// the full run loop, signal handling, and ordered shutdown.
    ///
    /// This replaces the hand-built `ServiceGroup` that consumers previously
    /// wired around their transports. It:
    ///
    /// 1. Runs every transport inside a `ServiceGroup`, trapping
    ///    `gracefulShutdownSignals` (SIGTERM/SIGINT by default).
    /// 2. For each connection a transport accepts, pumps its
    ///    ``MCPConnection/inbound`` frames through
    ///    ``processBatch(_:ignoringEmptyResponses:)`` and writes any responses
    ///    back via `send(_:)`. A per-connection ``Session``
    ///    is bound as `Session.current` for the duration, so outbound
    ///    notifications and server→client requests flow over the same connection.
    /// 3. Calls ``shutdown()`` once the transport group has fully stopped.
    ///
    /// ### Shutdown correctness, owned once
    ///
    /// Both `successTerminationBehavior` and `failureTerminationBehavior` are set
    /// to `.gracefullyShutdownGroup`. The default failure behavior
    /// (`.cancelGroup`) cancels every service *concurrently* on a single
    /// transport failure, which can race ordered teardown (a successor grabbing a
    /// lock mid-drain). Graceful failure handling instead unwinds the group in
    /// reverse-registration order. Because ``shutdown()`` runs strictly after the
    /// group returns, your server's teardown is always the very last step — on
    /// success, on a signal, and on failure alike.
    ///
    /// - Parameters:
    ///   - transports: The transports to accept connections from. They are
    ///     registered in order, and the group tears them down in reverse.
    ///   - gracefulShutdownSignals: Unix signals that trigger a graceful
    ///     shutdown. Defaults to `[.sigterm, .sigint]`.
    ///   - logger: Logger used for the service group and connection routing.
    /// - Throws: Rethrows the first transport failure after the group has shut
    ///   down gracefully and ``shutdown()`` has run.
    func serve(
        over transports: [any MCPTransport],
        gracefulShutdownSignals: [UnixSignal] = [.sigterm, .sigint],
        logger: Logger
    ) async throws where Self: Sendable {
        let group = ServiceGroup(
            configuration: .init(
                services: transports.map { transport in
                    .init(
                        service: transport,
                        successTerminationBehavior: .gracefullyShutdownGroup,
                        failureTerminationBehavior: .gracefullyShutdownGroup
                    )
                },
                gracefulShutdownSignals: gracefulShutdownSignals,
                logger: logger
            )
        )

        // Run the service group and the per-transport routing concurrently. The
        // group is the lifecycle anchor: when `group.run()` returns, every
        // transport has stopped (in reverse order), so we cancel routing and let
        // the connection streams drain.
        let outcome: Result<Void, Error>
        do {
            try await withThrowingTaskGroup(of: ServeTask.self) { tasks in
                tasks.addTask {
                    try await group.run()
                    return .group
                }
                for transport in transports {
                    tasks.addTask {
                        await routeConnections(of: transport, logger: logger)
                        return .router
                    }
                }

                // Wait specifically for the service group to finish; routers may
                // end earlier (e.g. a transport closing its connection stream on
                // EOF), in which case we keep waiting for the group.
                while let task = try await tasks.next() {
                    if case .group = task { break }
                }
                tasks.cancelAll()
            }
            outcome = .success(())
        } catch {
            outcome = .failure(error)
        }

        // Ordered on every path: server teardown runs after the transport group
        // has fully stopped.
        await shutdown()

        try outcome.get()
    }

    // MARK: - Routing

    /// Drains one transport's connections, routing each on its own child task so
    /// connections are served concurrently.
    private func routeConnections(
        of transport: any MCPTransport,
        logger: Logger
    ) async where Self: Sendable {
        await withTaskGroup(of: Void.self) { connectionTasks in
            for await connection in transport.connections {
                connectionTasks.addTask {
                    await route(connection: connection, logger: logger)
                }
            }
        }
    }

    /// Routes a single connection: binds a session, pumps inbound traffic through
    /// the server, and writes responses back.
    ///
    /// Each inbound item is processed on its own child task (which inherits the
    /// bound `Session.current`), so a long-running tool call — including one that
    /// awaits a server→client response such as `sampling`/`elicitation`/`roots` —
    /// never blocks reading the next inbound item, including that very response.
    /// A ``MCPBatchConnection`` routes whole frames through ``processBatch(_:ignoringEmptyResponses:)``;
    /// a plain ``MCPConnection`` routes single messages through ``handleMessage(_:)``.
    private func route(
        connection: any MCPConnection,
        logger: Logger
    ) async where Self: Sendable {
        // Scoped connections (HTTP+SSE) own their `Session` and supply a per-frame
        // outbound scope; `serve` is then a pure pump that dispatches inside each
        // frame's `within`. See ``MCPScopedConnection``.
        if let scoped = connection as? MCPScopedConnection {
            await routeScoped(connection: scoped, logger: logger)
            return
        }

        let session = Session(id: UUID())
        // The session writes outbound bytes through its (weakly held) transport;
        // back it with an adapter that forwards to this connection. Kept alive
        // for the whole connection via `withExtendedLifetime` below.
        let outbound = MCPConnectionTransport(connection: connection, logger: logger)
        await session.setTransport(outbound)

        await session.work { _ in
            await withTaskGroup(of: Void.self) { tasks in
                if let batchConnection = connection as? MCPBatchConnection {
                    for await frame in batchConnection.inboundBatches {
                        // The gate runs sequentially in the read loop so the
                        // initialize flag is settled before the next item is
                        // admitted; dispatch then runs concurrently so reads keep
                        // flowing (mid-call responses are not blocked).
                        guard await admit(frame, on: batchConnection, session: session) else { continue }
                        tasks.addTask {
                            await dispatchFrame(frame, on: batchConnection, logger: logger)
                        }
                    }
                } else {
                    for await message in connection.inbound {
                        guard await admit([message], on: connection, session: session) else { continue }
                        tasks.addTask {
                            await dispatchMessage(message, on: connection, logger: logger)
                        }
                    }
                }
            }
        }

        withExtendedLifetime(outbound) {}
    }

    /// Pumps a scoped connection: each pre-gated frame is dispatched on its own
    /// child task inside the frame's ``MCPInboundFrame/within`` scope, which binds
    /// the connection's `Session.current` (and per-request outbound routing). The
    /// connection owns session lifecycle and gating, so `serve` neither mints a
    /// session nor re-runs the initialize gate here.
    private func routeScoped(
        connection: any MCPScopedConnection,
        logger: Logger
    ) async where Self: Sendable {
        await withTaskGroup(of: Void.self) { tasks in
            for await frame in connection.scopedInbound {
                tasks.addTask {
                    await frame.within {
                        await dispatchScoped(frame.messages, on: connection, logger: logger)
                    }
                }
            }
        }
    }

    /// Dispatches an admitted scoped frame through ``processBatch(_:ignoringEmptyResponses:)``
    /// and writes each response back via the connection (which routes it to the
    /// frame's reply destination using the scope bound by `within`).
    private func dispatchScoped(
        _ messages: [JSONRPCMessage],
        on connection: any MCPConnection,
        logger: Logger
    ) async where Self: Sendable {
        let responses = await processBatch(messages)
        for response in responses {
            do {
                try await connection.send(response)
            } catch {
                logger.error("serve: failed to send response: \(error)")
            }
        }
    }

    /// Sequentially applies the initialize-ordering gate to an inbound frame.
    ///
    /// A frame beginning with `initialize` opens the session — marked here, before
    /// the concurrently-dispatched follow-ups are admitted, so they don't race the
    /// initialize handler and get spuriously rejected. Non-initialize requests
    /// arriving before initialization are rejected (parity with the byte-stream
    /// transports). Returns `true` if the frame should be dispatched.
    private func admit(
        _ frame: [JSONRPCMessage],
        on connection: any MCPConnection,
        session: Session
    ) async -> Bool {
        if SessionInitializationGate.batchStartsWithInitialize(frame) {
            await session.markInitializeRequestReceived()
            return true
        }
        if await SessionInitializationGate.shouldReject(frame, for: session) {
            for rejection in SessionInitializationGate.rejectionResponses(for: frame) {
                try? await connection.send(rejection)
            }
            return false
        }
        return true
    }

    /// Dispatches a single admitted message through ``handleMessage(_:)`` and
    /// writes any reply back.
    private func dispatchMessage(
        _ message: JSONRPCMessage,
        on connection: any MCPConnection,
        logger: Logger
    ) async where Self: Sendable {
        guard let response = await handleMessage(message) else { return }
        do {
            try await connection.send(response)
        } catch {
            logger.error("serve: failed to send response: \(error)")
        }
    }

    /// Dispatches a whole admitted frame: applies the version-gated batch reject
    /// (matching the legacy stdio/TCP/HTTP routes), runs
    /// ``processBatch(_:ignoringEmptyResponses:)``, and writes any responses back
    /// as one frame.
    private func dispatchFrame(
        _ frame: [JSONRPCMessage],
        on connection: any MCPBatchConnection,
        logger: Logger
    ) async where Self: Sendable {
        guard let session = Session.current else { return }

        // Reject batches on protocol revisions that removed batching (2025-06-18+).
        let version = await JSONRPCMessage.batchingVersion(for: frame, session: session)
        if JSONRPCMessage.batchingRejected(frame: frame, version: version) {
            try? await connection.send([JSONRPCMessage.batchingRejectionResponse(version: version)])
            return
        }

        let responses = await processBatch(frame)
        guard !responses.isEmpty else { return }
        do {
            try await connection.send(responses)
        } catch {
            logger.error("serve: failed to send response frame: \(error)")
        }
    }
}

/// Identifies which concurrent child finished inside `serve(over:)`.
private enum ServeTask {
    case group
    case router
}
#endif
