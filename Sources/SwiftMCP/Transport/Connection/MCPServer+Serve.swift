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

    /// Pumps one connection: binds its `Session.current` and dispatches each
    /// inbound frame inside the frame's ``MCPInboundFrame/within`` scope.
    ///
    /// The connection owns its session. If that session has no transport of its
    /// own — a one-socket ``BasicConnection`` — `serve` wires an adapter that
    /// forwards the session's outbound bytes to the connection; HTTP+SSE already
    /// attaches its own. The gate runs sequentially in the read loop (so the
    /// initialize flag settles before the next frame is admitted), while dispatch
    /// runs on its own child task — so a tool awaiting a server→client response
    /// (`sampling`/`elicitation`/`roots`) never blocks reading that very response.
    private func route(
        connection: any MCPConnection,
        logger: Logger
    ) async where Self: Sendable {
        let session = connection.session

        // Wire the session's outbound to the connection unless it already has a
        // transport. Held alive for the connection via `withExtendedLifetime`.
        let outbound: MCPConnectionTransport?
        if await session.transport == nil {
            let shim = MCPConnectionTransport(connection: connection, logger: logger)
            await session.setTransport(shim)
            outbound = shim
        } else {
            outbound = nil
        }

        await session.work { _ in
            await withTaskGroup(of: Void.self) { tasks in
                for await frame in connection.inbound {
                    guard await admit(frame.messages, on: connection, session: session) else { continue }
                    tasks.addTask {
                        await frame.within {
                            await dispatch(frame.messages, on: connection, logger: logger)
                        }
                    }
                }
            }
        }

        withExtendedLifetime(outbound) {}
    }

    /// Sequentially gates an inbound frame against the bound session.
    ///
    /// A frame beginning with `initialize` opens the session — marked here, before
    /// the concurrently-dispatched follow-ups are admitted, so they don't race the
    /// initialize handler and get spuriously rejected. Non-initialize requests
    /// before initialization, and batches on protocol revisions that removed
    /// batching (`2025-06-18`+), are rejected. Returns `true` to dispatch.
    private func admit(
        _ messages: [JSONRPCMessage],
        on connection: any MCPConnection,
        session: Session
    ) async -> Bool {
        if SessionInitializationGate.batchStartsWithInitialize(messages) {
            await session.markInitializeRequestReceived()
            return true
        }
        if await SessionInitializationGate.shouldReject(messages, for: session) {
            let rejections = SessionInitializationGate.rejectionResponses(for: messages)
            if !rejections.isEmpty {
                try? await connection.send(rejections)
            }
            return false
        }
        let version = await JSONRPCMessage.batchingVersion(for: messages, session: session)
        if JSONRPCMessage.batchingRejected(frame: messages, version: version) {
            try? await connection.send([JSONRPCMessage.batchingRejectionResponse(version: version)])
            return false
        }
        return true
    }

    /// Dispatches an admitted frame through ``processBatch(_:ignoringEmptyResponses:)``
    /// and writes any responses back through the connection (which routes them to
    /// the frame's reply destination, using the scope bound by `within`).
    private func dispatch(
        _ messages: [JSONRPCMessage],
        on connection: any MCPConnection,
        logger: Logger
    ) async where Self: Sendable {
        let responses = await processBatch(messages)
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
