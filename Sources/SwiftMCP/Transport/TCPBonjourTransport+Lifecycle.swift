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
    }

    public func run() async throws {
        try await start()
        // Inside a `ServiceGroup`, a graceful shutdown signal calls `stop()`,
        // which cancels the listener/connections and resumes `waitUntilStopped()`
        // so this method returns. Standalone callers drive shutdown via `stop()`.
        await withGracefulShutdownHandler {
            await state.waitUntilStopped()
        } onGracefulShutdown: { [weak self] in
            Task { [weak self] in try? await self?.stop() }
        }
        // End the connection-based stream so any `serve(over:)` routing loop
        // consuming `connections` unwinds.
        connectionsContinuation.finish()
    }

    public func stop() async throws {
        await state.stop()
    }

    // MARK: - Send

    public func send(_ data: Data) async throws {
        guard let currentSession = Session.current else {
            throw TransportError.bindingFailed("No active session for send")
        }

        guard let connection = await state.connection(for: currentSession.id) else {
            throw TransportError.bindingFailed("TCP connection unavailable for session \(currentSession.id)")
        }

        let string = String(data: data, encoding: .utf8) ?? ""
        logger.trace("TCP OUT:\n\n\(string)")

        var out = data
        out.append(Data("\n".utf8))

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: out, completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            })
        }
    }
}
#endif
#endif
