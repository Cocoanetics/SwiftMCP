//
//  MCPServer+Serve.swift
//  SwiftMCP
//
//  `serve(over:)` — runs decoupled transports against this server — plus the
//  `shutdown()` lifecycle hook. Gated behind `Server` because it builds a
//  swift-service-lifecycle `ServiceGroup`.
//

#if Server
import Foundation
import Logging
import ServiceLifecycle
import UnixSignals

public extension MCPServer {
    /// Serves this server over one or more transports, owning the full run loop,
    /// signal handling, and ordered shutdown.
    ///
    /// This replaces the hand-built `ServiceGroup` that consumers previously wired
    /// around their transports. It:
    ///
    /// 1. Builds an ``MCPDispatcher`` over this server (applying the
    ///    initialize/batch gate, then dispatching through
    ///    ``processBatch(_:ignoringEmptyResponses:)``) and hands it to every
    ///    transport via ``MCPTransport/connect(to:)``.
    /// 2. Runs every transport inside a `ServiceGroup`, trapping
    ///    `gracefulShutdownSignals` (SIGTERM/SIGINT by default). Each transport
    ///    reads its own wire and calls the dispatcher's `handle`; `serve` owns no
    ///    routing of its own.
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
    ///   - transports: The transports to serve over. They are registered in
    ///     order, and the group tears them down in reverse.
    ///   - gracefulShutdownSignals: Unix signals that trigger a graceful
    ///     shutdown. Defaults to `[.sigterm, .sigint]`.
    ///   - logger: Logger used for the service group.
    /// - Throws: Rethrows the first transport failure after the group has shut
    ///   down gracefully and ``shutdown()`` has run.
    func serve(
        over transports: [any MCPTransport],
        gracefulShutdownSignals: [UnixSignal] = [.sigterm, .sigint],
        logger: Logger
    ) async throws where Self: Sendable {
        // Every transport routes its inbound payloads through this one dispatcher.
        let dispatcher = MCPServerDispatcher(server: self)
        for transport in transports {
            transport.connect(to: dispatcher)
        }

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

        // The group is the lifecycle anchor: when `run()` returns, every transport
        // has stopped (in reverse order).
        let outcome: Result<Void, Error>
        do {
            try await group.run()
            outcome = .success(())
        } catch {
            outcome = .failure(error)
        }

        // Ordered on every path: server teardown runs after the transport group
        // has fully stopped.
        await shutdown()

        try outcome.get()
    }
}
#endif
