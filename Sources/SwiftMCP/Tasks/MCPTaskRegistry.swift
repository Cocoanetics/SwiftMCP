//
//  MCPTaskRegistry.swift
//  SwiftMCP
//
//  Process-wide store for official Tasks-extension tasks. Modern HTTP sessions
//  are ephemeral, so task state cannot live on ``Session``.
//

import Foundation

/// Registry of in-flight and recently completed tasks.
public actor MCPTaskRegistry {
    /// Shared store used by the server runtime.
    public static let shared = MCPTaskRegistry()

    private var tasks: [String: MCPTaskRecord] = [:]
    private var defaultTTLMs: Int? = MCPTasksExtension.defaultTTLMs
    private var defaultPollIntervalMs: Int = MCPTasksExtension.defaultPollIntervalMs

    /// Overrides the default TTL for newly created tasks (`nil` = unlimited).
    public func setDefaultTTLMs(_ value: Int?) {
        defaultTTLMs = value
    }

    /// Overrides the default poll interval for newly created tasks.
    public func setDefaultPollIntervalMs(_ value: Int) {
        defaultPollIntervalMs = value
    }

    /// Removes every task — test seam.
    public func removeAll() {
        tasks.removeAll()
    }

    /// Creates a new task owned by `owner` and registers it before returning,
    /// so a subsequent `tasks/get` for the returned id is durable.
    public func create(
        owner: MCPTaskPrincipal,
        ttlMs: Int? = nil,
        pollIntervalMs: Int? = nil
    ) async -> MCPTaskRecord {
        await purgeExpired()
        let taskId = UUID().uuidString
        let record = MCPTaskRecord(
            taskId: taskId,
            owner: owner,
            ttlMs: ttlMs ?? defaultTTLMs,
            pollIntervalMs: pollIntervalMs ?? defaultPollIntervalMs
        )
        tasks[taskId] = record
        return record
    }

    /// Looks up a task the caller is allowed to see.
    ///
    /// - Returns: The task, or `nil` when missing, expired (purged), or owned by
    ///   a different principal (existence is not leaked across principals).
    public func task(id taskId: String, for owner: MCPTaskPrincipal) async -> MCPTaskRecord? {
        await purgeExpired()
        guard let record = tasks[taskId] else { return nil }
        let recordOwner = await record.owner
        guard recordOwner == owner else { return nil }
        if await record.isExpired {
            await discardExpired(record, id: taskId)
            return nil
        }
        return record
    }

    /// Drops a task from the registry (e.g. after an explicit purge).
    public func remove(id taskId: String) {
        tasks.removeValue(forKey: taskId)
    }

    /// Removes every task whose TTL has elapsed, so abandoned records do not
    /// accumulate when clients stop polling. Cancels in-flight work and resumes
    /// any pending input waits before dropping the record.
    func purgeExpired() async {
        for (id, record) in Array(tasks) {
            guard await record.isExpired else { continue }
            await discardExpired(record, id: id)
        }
    }

    /// Tears down an expired task so its unstructured work and input
    /// continuations cannot leak after the registry forgets it.
    private func discardExpired(_ record: MCPTaskRecord, id: String) async {
        await record.requestCancellation()
        tasks.removeValue(forKey: id)
    }
}
