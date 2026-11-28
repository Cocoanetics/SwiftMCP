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
/// ``retire()`` refuses new starts from then on, fails and cancels the
/// registered ones, and only invalidates the session once none of them can
/// still create a task. A retired session never comes back, so a request that
/// captured it can never migrate onto the session of a later connection.
internal final class MCPProxyHTTPSession: @unchecked Sendable {
    let session: URLSession

    private let lock = NSLock()
    private var isRetired = false
    private var isInvalidated = false
    private var nextID = 0
    /// Fails and cancels the starts that may still create a Foundation task, by id.
    private var pendingStarts: [Int: @Sendable () -> Void] = [:]
    /// Cancels the operations running on this session (see ``run(_:)``), by id.
    private var activeOperations: [Int: @Sendable () -> Void] = [:]
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

    /// Runs `operation` (a whole request, including reading its body) in a task
    /// that ``retire()`` cancels. Invalidating the session alone does not end
    /// every stream: off Apple platforms SwiftCross's `bytes(for:)` reads on a
    /// one-shot session of its own, which only task cancellation reaches.
    func run<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        let (operationID, task) = try registerOperation(operation)
        defer { lock.withLock { activeOperations[operationID] = nil } }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    /// Refuses further starts, ends in-flight work, and invalidates the
    /// session as soon as no start can still create a task on it.
    func retire() {
        let pending: [@Sendable () -> Void]
        let operations: [@Sendable () -> Void]
        let invalidateNow: Bool
        lock.lock()
        if isRetired {
            lock.unlock()
            return
        }
        isRetired = true
        pending = Array(pendingStarts.values)
        operations = Array(activeOperations.values)
        invalidateNow = pending.isEmpty
        if invalidateNow {
            isInvalidated = true
        }
        lock.unlock()

        for cancel in operations {
            cancel()
        }
        if invalidateNow {
            session.invalidateAndCancel()
            return
        }

        // Starts still in flight will invalidate the session when the last one
        // finishes; until then fail them and cancel every task already running.
        for cancel in pending {
            cancel()
        }
        session.getAllTasks { tasks in
            for task in tasks {
                task.cancel()
            }
        }
    }

    internal func start<Value>(
        _ operation: @escaping @Sendable (URLSession) async throws -> Value
    ) async throws -> Value {
        if let gate = lock.withLock({ startGate }) {
            await gate()
        }

        let pending = PendingStart<UncheckedSendableBox<Value>>()
        try registerStart(pending, operation)
        let result = try await withTaskCancellationHandler {
            try await pending.value()
        } onCancel: {
            pending.cancel()
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
    /// The caller waits on `pending`, which ``retire()`` fails directly: the
    /// SwiftCross `bytes(for:)` shim ignores cancellation until headers arrive.
    private func registerStart<Value>(
        _ pending: PendingStart<UncheckedSendableBox<Value>>,
        _ operation: @escaping @Sendable (URLSession) async throws -> Value
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        guard !isRetired else {
            throw CancellationError()
        }
        let startID = nextID
        nextID += 1
        startedTaskCount += 1
        let session = self.session
        let task = Task {
            let result: Result<UncheckedSendableBox<Value>, Error>
            do {
                result = .success(UncheckedSendableBox(value: try await operation(session)))
            } catch {
                result = .failure(error)
            }
            self.finishStart(startID)
            pending.resolve(result)
        }
        pending.setTask(task)
        pendingStarts[startID] = { pending.cancel() }
    }

    private func registerOperation<Value: Sendable>(
        _ operation: @escaping @Sendable () async throws -> Value
    ) throws -> (Int, Task<Value, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !isRetired else {
            throw CancellationError()
        }
        let operationID = nextID
        nextID += 1
        let task = Task { try await operation() }
        activeOperations[operationID] = { task.cancel() }
        return (operationID, task)
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

/// The caller's side of one start: resolved by whichever comes first — the
/// Foundation call finishing, the caller being cancelled, or ``MCPProxyHTTPSession/retire()``.
private final class PendingStart<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Value, Error>?
    private var continuation: CheckedContinuation<Value, Error>?
    private var task: Task<Void, Never>?

    func setTask(_ task: Task<Void, Never>) {
        lock.withLock { self.task = task }
    }

    func value() async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            if let result = install(continuation) {
                continuation.resume(with: result)
            }
        }
    }

    /// Fails the waiting caller now and cancels the Foundation call behind it.
    func cancel() {
        let task = lock.withLock { self.task }
        resolve(.failure(CancellationError()))
        task?.cancel()
    }

    func resolve(_ newResult: Result<Value, Error>) {
        let waiting: CheckedContinuation<Value, Error>? = lock.withLock {
            guard result == nil else { return nil }
            result = newResult
            defer { continuation = nil }
            return continuation
        }
        waiting?.resume(with: newResult)
    }

    /// Stores the caller's continuation, or returns the result if it is already in.
    private func install(_ continuation: CheckedContinuation<Value, Error>) -> Result<Value, Error>? {
        lock.withLock {
            if let result {
                return result
            }
            self.continuation = continuation
            return nil
        }
    }
}

/// Carries a Foundation value that predates `Sendable` (`URLSession.AsyncBytes`)
/// out of the start task; it is handed over once and never shared.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
}
#endif
