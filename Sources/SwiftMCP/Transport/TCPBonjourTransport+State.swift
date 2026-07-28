//
//  TCPBonjourTransport+State.swift
//  SwiftMCP
//
//  The transport's lifecycle state machine: one actor owning the listener, the
//  live connections (each with its task tracker), retry/watchdog tasks, and the
//  run-loop continuation. Every guard in here exists because some teardown path
//  races another; see #171 for the full audit.
//

#if Server
import Foundation

#if canImport(Network)
import Network

/// A live inbound connection and the dispatch tasks it spawned.
///
/// The task tracker travels with the connection so that tearing one down also
/// cancels every in-flight line handler — a long-running tool must not keep
/// working for a client that is gone.
internal struct TCPConnectionEntry {
    let connection: NWConnection
    let tasks: ConnectionTaskTracker
}

extension TCPBonjourTransport {
    internal actor TransportState {
        private(set) var isRunning: Bool = false
        private(set) var generation: UInt64 = 0
        private var listener: NWListener?
        private var connections: [UUID: TCPConnectionEntry] = [:]
        private var runContinuation: CheckedContinuation<Void, Never>?
        private var retryTask: Task<Void, Never>?
        private var watchdogTask: Task<Void, Never>?
        private var localRegistration: LocalOnlyRegistration?
        private(set) var retryAttempt: Int = 0

        /// The unrecoverable failure that stopped the transport, if any.
        /// Rethrown by ``waitUntilStopped()`` so `run()` surfaces it instead of
        /// parking forever on a transport that can no longer accept anything.
        private(set) var terminalError: Error?

        func running() -> Bool {
            isRunning
        }

        /// Start a new listener generation.
        /// Returns the generation token for this listener.
        @discardableResult
        func start(listener: NWListener) -> UInt64 {
            generation += 1
            self.listener = listener
            isRunning = true
            retryAttempt = 0
            terminalError = nil  // a restarted transport must not rethrow a stale failure
            cancelRetryTask()
            localRegistration?.stop()
            localRegistration = nil
            return generation
        }

        /// Replace the current listener with a new one during retry recovery.
        /// Returns the new generation token, or nil if the transport is stopped.
        func replaceListener(_ newListener: NWListener, expectedGeneration: UInt64) -> UInt64? {
            guard isRunning, generation == expectedGeneration else {
                return nil
            }
            listener?.cancel()
            localRegistration?.stop()
            localRegistration = nil
            generation += 1
            self.listener = newListener
            return generation
        }

        func stop() {
            isRunning = false
            generation += 1  // invalidate any in-flight retry / state callbacks
            cancelRetryTask()
            watchdogTask?.cancel()
            watchdogTask = nil
            retryAttempt = 0
            listener?.cancel()
            listener = nil
            localRegistration?.stop()
            localRegistration = nil
            for entry in connections.values {
                entry.connection.cancel()
                entry.tasks.cancelAll()
            }
            connections.removeAll()
            if let continuation = runContinuation {
                runContinuation = nil
                continuation.resume()
            }
        }

        /// Stop the transport because of an unrecoverable failure tied to the
        /// given listener generation. A no-op for stale generations, so a retry
        /// that already replaced the listener cannot kill its successor.
        func fail(generation listenerGen: UInt64, _ error: Error) {
            guard listenerGen == generation else { return }
            failTerminally(error)
        }

        /// Stop the transport because of an unrecoverable failure that is not
        /// tied to a listener generation (descriptor exhaustion detected on a
        /// connection or by the watchdog).
        func failTerminally(_ error: Error) {
            guard isRunning else { return }
            terminalError = error
            stop()
        }

        func waitUntilStopped() async throws {
            if isRunning {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    runContinuation = continuation
                }
            }
            if let terminalError {
                throw terminalError
            }
        }

        /// Called when the listener reaches `.ready`.
        /// Resets backoff, clears any pending retry, and returns the bound port (if available).
        func listenerReady(generation listenerGen: UInt64) -> UInt16? {
            guard listenerGen == generation, isRunning else { return nil }
            retryAttempt = 0
            cancelRetryTask()
            return listener?.port?.rawValue
        }

        func setLocalRegistration(
            _ registration: LocalOnlyRegistration,
            generation listenerGen: UInt64
        ) -> Bool {
            guard listenerGen == generation, isRunning else { return false }
            localRegistration?.stop()
            localRegistration = registration
            return true
        }

        /// Replaces the listener's advertised service, e.g. to publish a TXT record
        /// that could not be complete when the listener was created.
        func updateService(_ service: NWListener.Service, generation listenerGen: UInt64) {
            guard listenerGen == generation, isRunning else { return }
            listener?.service = service
        }

        func removeLocalRegistration(generation listenerGen: UInt64) {
            guard listenerGen == generation else { return }
            localRegistration?.stop()
            localRegistration = nil
        }

        /// Called when the listener fails with a retryable error.
        /// Increments the backoff attempt and returns the delay in seconds,
        /// or nil if the transport is stopped or the generation is stale.
        func listenerFailed(generation listenerGen: UInt64) -> UInt64? {
            guard listenerGen == generation, isRunning else { return nil }
            retryAttempt += 1
            let delay = min(UInt64(1) << UInt64(min(retryAttempt - 1, 5)), TCPBonjourTransport.maxRetryDelay)
            return delay
        }

        /// Store a retry task. Cancels any existing one first.
        func setRetryTask(_ task: Task<Void, Never>) {
            cancelRetryTask()
            retryTask = task
        }

        private func cancelRetryTask() {
            retryTask?.cancel()
            retryTask = nil
        }

        /// Store the descriptor watchdog task. Cancelled by `stop()`.
        func setWatchdogTask(_ task: Task<Void, Never>) {
            watchdogTask?.cancel()
            watchdogTask = task
        }

        /// Register an accepted connection, or refuse it when the transport has
        /// already stopped — `handleNewConnection` suspends before registering,
        /// so a connection accepted around `stop()` would otherwise be added
        /// after `stop()`'s sweep and live on a shut-down transport.
        func addConnection(id: UUID, connection: NWConnection, tasks: ConnectionTaskTracker) -> Bool {
            guard isRunning else { return false }
            connections[id] = TCPConnectionEntry(connection: connection, tasks: tasks)
            return true
        }

        /// Remove and tear down one connection.
        ///
        /// Network.framework only releases the underlying socket on `cancel()`;
        /// dropping the last reference leaks both the descriptor and the
        /// self-retained `NWConnection`. Cancelling inside the actor keeps two
        /// racing teardown paths (receive error vs `.failed`) from both acting:
        /// the second entry removes nothing and is a no-op.
        func removeConnection(id: UUID) {
            guard let entry = connections.removeValue(forKey: id) else { return }
            entry.connection.cancel()
            entry.tasks.cancelAll()
        }

        func connection(for id: UUID) -> NWConnection? {
            connections[id]?.connection
        }
    }
}
#endif
#endif
