//
//  MCPTaskRecord.swift
//  SwiftMCP
//
//  In-memory state machine for one official Tasks-extension task. Survives
//  across modern (sessionless) requests via ``MCPTaskRegistry``.
//

import Foundation

/// One durable task under `io.modelcontextprotocol/tasks`.
public actor MCPTaskRecord {
    /// The task currently executing tool work, if any.
    @TaskLocal
    public static var current: MCPTaskRecord?

    public let taskId: String
    public let owner: MCPTaskPrincipal
    public let createdAt: Date

    public private(set) var status: MCPTaskStatus = .working
    public private(set) var statusMessage: String?
    public private(set) var lastUpdatedAt: Date
    public private(set) var ttlMs: Int?
    public private(set) var pollIntervalMs: Int?
    public private(set) var inputRequests: [String: InputRequest] = [:]
    public private(set) var result: JSONDictionary?
    public private(set) var error: JSONRPCError?

    private var work: Task<Void, Never>?
    private var cancellationRequested = false
    private var inputOrdinal = 0
    private var pendingInputs: [String: CheckedContinuation<JSONValue, Error>] = [:]

    init(
        taskId: String,
        owner: MCPTaskPrincipal,
        ttlMs: Int?,
        pollIntervalMs: Int?,
        createdAt: Date = Date()
    ) {
        self.taskId = taskId
        self.owner = owner
        self.ttlMs = ttlMs
        self.pollIntervalMs = pollIntervalMs
        self.createdAt = createdAt
        self.lastUpdatedAt = createdAt
    }

    /// Whether the TTL has elapsed (non-null TTL only).
    public var isExpired: Bool {
        guard let ttlMs else { return false }
        let deadline = createdAt.addingTimeInterval(Double(ttlMs) / 1_000)
        return Date() > deadline
    }

    /// Observable snapshot for wire responses.
    public func snapshot() -> MCPTaskSnapshot {
        MCPTaskSnapshot(
            taskId: taskId,
            status: status,
            statusMessage: statusMessage,
            createdAt: createdAt,
            lastUpdatedAt: lastUpdatedAt,
            ttlMs: ttlMs,
            pollIntervalMs: pollIntervalMs,
            inputRequests: status == .inputRequired ? inputRequests : nil,
            result: status == .completed ? result : nil,
            error: status == .failed ? error : nil
        )
    }

    /// Starts the unstructured work body for this task.
    func startWork(_ operation: @escaping @Sendable () async -> Void) {
        work = Task {
            await operation()
        }
    }

    /// Marks the task completed with the underlying method result.
    func complete(with result: JSONDictionary, statusMessage: String? = nil) {
        guard !status.isTerminal else { return }
        self.result = result
        self.status = .completed
        self.statusMessage = statusMessage
        self.inputRequests = [:]
        touch()
        failPendingInputs(CancellationError())
    }

    /// Marks the task failed with a JSON-RPC error.
    func fail(with error: JSONRPCError, statusMessage: String? = nil) {
        guard !status.isTerminal else { return }
        self.error = error
        self.status = .failed
        self.statusMessage = statusMessage ?? error.message
        self.inputRequests = [:]
        touch()
        failPendingInputs(CancellationError())
    }

    /// Requests cooperative cancellation.
    func requestCancellation() {
        cancellationRequested = true
        work?.cancel()
        if !status.isTerminal {
            status = .cancelled
            statusMessage = "Cancelled"
            inputRequests = [:]
            touch()
            failPendingInputs(CancellationError())
        }
    }

    /// Whether cancellation was requested (for the work body to distinguish
    /// cooperative cancel from other failures).
    func wasCancellationRequested() -> Bool {
        cancellationRequested
    }

    /// Surfaces a server→client input request and waits for `tasks/update`.
    func awaitInput(
        method: String,
        params: JSONValue?
    ) async throws -> JSONValue {
        let key = "input-\(inputOrdinal)"
        inputOrdinal += 1
        inputRequests[key] = InputRequest(method: method, params: params)
        status = .inputRequired
        statusMessage = nil
        touch()

        return try await withCheckedThrowingContinuation { continuation in
            pendingInputs[key] = continuation
        }
    }

    /// Applies client `inputResponses` for currently outstanding keys.
    /// Unknown / already-satisfied keys are ignored (spec).
    func applyInputResponses(_ responses: JSONDictionary) {
        guard !status.isTerminal else { return }
        for (key, value) in responses {
            guard let continuation = pendingInputs.removeValue(forKey: key) else { continue }
            inputRequests.removeValue(forKey: key)
            continuation.resume(returning: value)
        }
        if inputRequests.isEmpty, status == .inputRequired {
            status = .working
            statusMessage = nil
        }
        touch()
    }

    private func touch() {
        lastUpdatedAt = Date()
    }

    private func failPendingInputs(_ error: Error) {
        let pending = pendingInputs
        pendingInputs = [:]
        for continuation in pending.values {
            continuation.resume(throwing: error)
        }
    }
}
