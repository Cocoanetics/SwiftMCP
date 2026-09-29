#if Server
import Foundation
import ServiceLifecycle

#if canImport(Network)
import Network

extension TCPBonjourTransport {
    // MARK: - Lifecycle

    public func start() async throws {
        if await state.running() {
            return
        }

        let listener = try createListener()
        let generation = await state.start(listener: listener)
        installStateHandler(on: listener, generation: generation)
        listener.start(queue: queue)
        startDescriptorWatchdog()
    }

    public func run() async throws {
        try await start()
        // Inside a `ServiceGroup`, a graceful shutdown signal calls `stop()`,
        // which cancels the listener/connections and resumes `waitUntilStopped()`
        // so this method returns. Standalone callers drive shutdown via `stop()`.
        // An unrecoverable failure (dead listener, descriptor exhaustion) is
        // rethrown here, so embedders learn about it instead of parking forever.
        try await withGracefulShutdownHandler {
            try await state.waitUntilStopped()
        } onGracefulShutdown: { [weak self] in
            Task { [weak self] in try? await self?.stop() }
        }
    }

    public func stop() async throws {
        await state.stop()
    }

    // MARK: - Disconnect

    /// Cancels the session's connection and cancels its in-flight requests, as when the
    /// client goes: a send waiting for the client to read ends with an error.
    public func disconnect(_ session: Session) async {
        await cleanupConnection(id: session.id)
    }

    // MARK: - Send

    public func send(_ data: Data) async throws {
        guard let currentSession = Session.current else {
            throw TransportError.bindingFailed("No active session for send")
        }

        guard let entry = await state.entry(for: currentSession.id) else {
            throw TransportError.bindingFailed("TCP connection unavailable for session \(currentSession.id)")
        }

        let string = String(data: data, encoding: .utf8) ?? ""
        logger.trace("TCP OUT:\n\n\(string)")

        var out = data
        out.append(Data("\n".utf8))

        try await entry.output.send(out, on: entry.connection)
    }
}
#endif
#endif
