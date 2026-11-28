#if Client
import SwiftCross

/// One connection's `URLSession`, with task creation and invalidation kept
/// mutually exclusive.
///
/// `URLSession.bytes(for:)` / `data(for:)` are nonisolated, so they create
/// their Foundation task *after* leaving the proxy actor. A `disconnect()` that
/// ran in between used to invalidate the session first, and Foundation then
/// raised an uncatchable `NSGenericException` ("Task created in a session that
/// has been invalidated") that aborted the process. (#277)
///
/// Every start is registered under ``lock`` before it may reach Foundation.
/// ``retire()`` refuses new starts from then on, cancels the registered ones,
/// and only invalidates the session once none of them can still create a task.
/// A retired session never comes back, so a request that captured it can never
/// migrate onto the session of a later connection.
internal final class MCPProxyHTTPSession: @unchecked Sendable {
    let session: URLSession

    private let lock = NSLock()
    private var isRetired = false
    private var isInvalidated = false
    private var nextStartID = 0
    /// Cancels the starts that may still create a Foundation task, by id.
    private var pendingStarts: [Int: @Sendable () -> Void] = [:]
    private var startedTaskCount = 0
    private var startGate: (@Sendable () async -> Void)?

    init(configuration: URLSessionConfiguration) {
        session = URLSession(configuration: configuration)
    }

    /// Whether ``retire()`` has been called.
    var retired: Bool {
        lock.withLock { isRetired }
    }

    /// How many Foundation requests this session has been allowed to start.
    var startedTasks: Int {
        lock.withLock { startedTaskCount }
    }

    /// Test seam: awaited by every request after it has captured this session
    /// but before it may start a task — the window `disconnect()` raced. (#277)
    func setStartGate(_ gate: (@Sendable () async -> Void)?) {
        lock.withLock { startGate = gate }
    }

    func bytes(for request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        try await start { session in try await session.bytes(for: request) }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await start { session in try await session.data(for: request) }
    }

    /// Refuses further starts, cancels in-flight work, and invalidates the
    /// session as soon as no start can still create a task on it.
    func retire() {
        let pending: [@Sendable () -> Void]
        let invalidateNow: Bool
        lock.lock()
        if isRetired {
            lock.unlock()
            return
        }
        isRetired = true
        pending = Array(pendingStarts.values)
        invalidateNow = pending.isEmpty
        if invalidateNow {
            isInvalidated = true
        }
        lock.unlock()

        if invalidateNow {
            session.invalidateAndCancel()
            return
        }

        // Starts still in flight will invalidate the session when the last one
        // finishes; until then cancel them and every task already running.
        for cancel in pending {
            cancel()
        }
        session.getAllTasks { tasks in
            for task in tasks {
                task.cancel()
            }
        }
    }

    private func start<Value>(
        _ operation: @escaping @Sendable (URLSession) async throws -> Value
    ) async throws -> Value {
        if let gate = lock.withLock({ startGate }) {
            await gate()
        }

        let (startID, task) = try registerStart(operation)
        defer { finishStart(startID) }
        let result = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        // The session was retired while the response was on its way; its
        // invalidation cancels the body, so do not hand the stale result back.
        if retired {
            throw CancellationError()
        }
        return result.value
    }

    /// Spawns the task that calls into Foundation while holding ``lock``, so it
    /// either exists before ``retire()`` looks for pending starts or is refused.
    private func registerStart<Value>(
        _ operation: @escaping @Sendable (URLSession) async throws -> Value
    ) throws -> (Int, Task<UncheckedSendableBox<Value>, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !isRetired else {
            throw CancellationError()
        }
        let startID = nextStartID
        nextStartID += 1
        startedTaskCount += 1
        let session = self.session
        let task = Task { UncheckedSendableBox(value: try await operation(session)) }
        pendingStarts[startID] = { task.cancel() }
        return (startID, task)
    }

    private func finishStart(_ startID: Int) {
        lock.lock()
        pendingStarts[startID] = nil
        let invalidate = isRetired && !isInvalidated && pendingStarts.isEmpty
        if invalidate {
            isInvalidated = true
        }
        lock.unlock()

        if invalidate {
            session.invalidateAndCancel()
        }
    }
}

/// Carries a Foundation value that predates `Sendable` (`URLSession.AsyncBytes`)
/// out of the start task; it is handed over once and never shared.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
#endif
