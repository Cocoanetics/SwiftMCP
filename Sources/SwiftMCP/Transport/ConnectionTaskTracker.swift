#if Server
import Foundation

/// Tracks the dispatch tasks spawned for one TCP connection so that tearing the
/// connection down also cancels every in-flight line handler.
///
/// A tool body that loops on `Task.isCancelled` (or any long-running handler)
/// would otherwise keep running forever after its client disconnected, holding
/// whatever resources it opened. `cleanupConnection` is reachable from three
/// racing paths (receive error, peer EOF, `.failed` state), so everything here
/// is idempotent: `Task.cancel()` is, and a second `cancelAll()` finds nothing.
///
/// A lock-protected class rather than an actor because tasks are spawned from
/// `NWConnection` receive callbacks — synchronous code on the connection's
/// dispatch queue that cannot hop onto an actor without unordering the stream.
final class ConnectionTaskTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var isCancelled = false

    /// Spawn `operation` as a tracked task. After `cancelAll()` the tracker
    /// refuses new work — the connection is gone, there is nobody to reply to.
    /// Completed tasks remove themselves, so the tracker does not grow with
    /// connection lifetime.
    func spawn(_ operation: @escaping @Sendable () async -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !isCancelled else { return }
        let id = UUID()
        // Created while holding the lock so the task is registered before
        // its self-removal can run; `remove(id)` blocks on the lock until
        // this scope exits.
        tasks[id] = Task { [weak self] in
            await operation()
            self?.remove(id)
        }
    }

    func cancelAll() {
        lock.lock()
        isCancelled = true
        let pending = tasks
        tasks.removeAll()
        lock.unlock()
        for task in pending.values {
            task.cancel()
        }
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return tasks.isEmpty
    }

    /// Waits until every tracked task has finished, or the deadline passes.
    ///
    /// Used by the clean-EOF teardown path: a half-closing peer keeps its read
    /// side open for replies to requests already in flight, so those handlers
    /// get to finish before the socket is cancelled. Polling rather than
    /// awaiting task values keeps this deadlock-free regardless of which task
    /// calls it, and the deadline bounds a hung handler (the subsequent
    /// `cancelAll()` reaps it).
    func drain(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !isEmpty, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        tasks.removeValue(forKey: id)
        lock.unlock()
    }
}
#endif
