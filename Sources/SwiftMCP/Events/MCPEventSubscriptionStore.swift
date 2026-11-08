//
//  MCPEventSubscriptionStore.swift
//  SwiftMCP
//
//  Persistence boundary for `events/subscribe` webhook subscriptions, with an
//  in-memory default and a JSON-file implementation. Phase 2 of #204: the
//  subscribe/unsubscribe lifecycle only, no delivery yet.
//

import Foundation

/// Hands out the default in-memory store of each server, so servers in one
/// process never share subscriptions unless they are given the same store.
///
/// A reference-type server (class or actor) gets one store per instance; a value
/// type has no identity, so its instances share one store per type.
final class MCPDefaultEventStoreRegistry: @unchecked Sendable {
    static let shared = MCPDefaultEventStoreRegistry()

    private final class Box {
        let store = MCPInMemoryEventSubscriptionStore()
    }

    private let lock = NSLock()
    private struct Entry {
        weak var owner: AnyObject?
        let box: Box
    }

    private var instances: [ObjectIdentifier: Entry] = [:]
    private var types: [String: Box] = [:]

    func store(for server: Any) -> any MCPEventSubscriptionStore {
        lock.lock()
        defer { lock.unlock() }
        if type(of: server) is AnyClass {
            // Drop entries of deallocated servers so identifiers cannot be reused stale.
            instances = instances.filter { $0.value.owner != nil }
            let object = server as AnyObject
            if let entry = instances[ObjectIdentifier(object)] { return entry.box.store }
            let box = Box()
            instances[ObjectIdentifier(object)] = Entry(owner: object, box: box)
            return box.store
        }
        let name = String(reflecting: type(of: server))
        if let box = types[name] { return box.store }
        let box = Box()
        types[name] = box
        return box.store
    }
}

/// Default store: subscriptions live in memory and are lost on restart.
public actor MCPInMemoryEventSubscriptionStore: MCPEventSubscriptionStore {
    private var records: [MCPEventSubscriptionKey: MCPEventSubscription] = [:]

    public init() {}

    public func upsert(
        _ subscription: MCPEventSubscription,
        now: Date
    ) async throws -> MCPEventUpsertResult {
        let result = Self.merge(subscription, into: records[subscription.key], now: now)
        // Lapsed records are dropped on write so they cannot accumulate.
        records = records.filter { !$0.value.isExpired(at: now) }
        records[subscription.key] = result.subscription
        return result
    }

    public func subscription(id: String, now: Date) async throws -> MCPEventSubscription? {
        records.values.first { $0.id == id && !$0.isExpired(at: now) }
    }

    public func subscriptions(principal: String?, now: Date) async throws -> [MCPEventSubscription] {
        records.values
            .filter { !$0.isExpired(at: now) && (principal == nil || $0.principal == principal) }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public func remove(key: MCPEventSubscriptionKey) async throws -> Bool {
        records.removeValue(forKey: key) != nil
    }

    public func revoke(principal: String) async throws -> [MCPEventSubscription] {
        let removed = records.filter { $0.key.principal == principal }
        for key in removed.keys { records.removeValue(forKey: key) }
        return Array(removed.values)
    }

    public func purgeExpired(now: Date) async throws -> [MCPEventSubscription] {
        let lapsed = records.filter { $0.value.isExpired(at: now) }
        for key in lapsed.keys { records.removeValue(forKey: key) }
        return Array(lapsed.values)
    }

    public func applyDeliveryOutcome(
        id: String,
        update: MCPEventSubscriptionDeliveryUpdate,
        now: Date,
        disableAfterConsecutiveFailures: Int
    ) async throws -> MCPEventSubscription? {
        guard let existing = records.values.first(where: { $0.id == id && !$0.isExpired(at: now) }) else {
            return nil
        }
        let updated = Self.applying(
            update, to: existing, now: now, disableAfterConsecutiveFailures: disableAfterConsecutiveFailures
        )
        records[existing.key] = updated
        return updated
    }

    /// Shared create-or-refresh rule of the bundled stores.
    static func merge(
        _ incoming: MCPEventSubscription,
        into existing: MCPEventSubscription?,
        now: Date
    ) -> MCPEventUpsertResult {
        guard let existing, !existing.isExpired(at: now) else {
            return (incoming, true)
        }
        var refreshed = existing
        refreshed.secret = incoming.secret
        refreshed.refreshedAt = incoming.refreshedAt
        refreshed.expiresAt = incoming.expiresAt
        refreshed.cursor = incoming.cursor
        // A subscribe refresh re-enables delivery after auto-disable.
        refreshed.isDeliveryActive = true
        refreshed.consecutiveDeliveryFailures = 0
        refreshed.failedSince = nil
        refreshed.lastDeliveryError = nil
        return (refreshed, false)
    }

    /// Shared delivery-state transition of the bundled stores.
    static func applying(
        _ update: MCPEventSubscriptionDeliveryUpdate,
        to subscription: MCPEventSubscription,
        now: Date,
        disableAfterConsecutiveFailures: Int
    ) -> MCPEventSubscription {
        var updated = subscription
        updated.lastDeliveryAt = now
        let threshold = max(1, disableAfterConsecutiveFailures)
        switch update {
        case .delivered:
            updated.consecutiveDeliveryFailures = 0
            updated.lastDeliveryError = nil
            updated.failedSince = nil
            updated.isDeliveryActive = true
        case .rejected(let error):
            updated.lastDeliveryError = error
            // Keep active: 410/413 and other permanent refusals do not auto-disable.
        case .failed(let error):
            updated.lastDeliveryError = error
            if updated.consecutiveDeliveryFailures == 0 { updated.failedSince = now }
            updated.consecutiveDeliveryFailures += 1
            if updated.consecutiveDeliveryFailures >= threshold {
                updated.isDeliveryActive = false
            }
        }
        return updated
    }
}

/// Store that persists subscriptions to a JSON file, so they survive restarts.
///
/// The whole file is rewritten atomically on every mutation, which suits the
/// modest subscription counts of a single server process.
public actor MCPFileEventSubscriptionStore: MCPEventSubscriptionStore {
    private let fileURL: URL
    private var records: [MCPEventSubscriptionKey: MCPEventSubscription]

    /// Opens (or creates on first write) the store at `fileURL`. An unreadable
    /// existing file throws rather than being overwritten.
    public init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.records = [:]

        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for subscription in try decoder.decode([MCPEventSubscription].self, from: data) {
            records[subscription.key] = subscription
        }
    }

    public func upsert(
        _ subscription: MCPEventSubscription,
        now: Date
    ) async throws -> MCPEventUpsertResult {
        let result = MCPInMemoryEventSubscriptionStore.merge(subscription, into: records[subscription.key], now: now)
        var updated = records.filter { !$0.value.isExpired(at: now) }
        updated[subscription.key] = result.subscription
        try save(updated)
        records = updated
        return result
    }

    public func subscription(id: String, now: Date) async throws -> MCPEventSubscription? {
        records.values.first { $0.id == id && !$0.isExpired(at: now) }
    }

    public func subscriptions(principal: String?, now: Date) async throws -> [MCPEventSubscription] {
        records.values
            .filter { !$0.isExpired(at: now) && (principal == nil || $0.principal == principal) }
            .sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
    }

    public func remove(key: MCPEventSubscriptionKey) async throws -> Bool {
        var updated = records
        guard updated.removeValue(forKey: key) != nil else { return false }
        try save(updated)
        records = updated
        return true
    }

    public func revoke(principal: String) async throws -> [MCPEventSubscription] {
        let removed = records.filter { $0.key.principal == principal }
        guard !removed.isEmpty else { return [] }
        var updated = records
        for key in removed.keys { updated.removeValue(forKey: key) }
        try save(updated)
        records = updated
        return Array(removed.values)
    }

    public func purgeExpired(now: Date) async throws -> [MCPEventSubscription] {
        let lapsed = records.filter { $0.value.isExpired(at: now) }
        guard !lapsed.isEmpty else { return [] }
        var updated = records
        for key in lapsed.keys { updated.removeValue(forKey: key) }
        try save(updated)
        records = updated
        return Array(lapsed.values)
    }

    public func applyDeliveryOutcome(
        id: String,
        update: MCPEventSubscriptionDeliveryUpdate,
        now: Date,
        disableAfterConsecutiveFailures: Int
    ) async throws -> MCPEventSubscription? {
        guard let existing = records.values.first(where: { $0.id == id && !$0.isExpired(at: now) }) else {
            return nil
        }
        let applied = MCPInMemoryEventSubscriptionStore.applying(
            update, to: existing, now: now, disableAfterConsecutiveFailures: disableAfterConsecutiveFailures
        )
        var updated = records
        updated[existing.key] = applied
        try save(updated)
        records = updated
        return applied
    }

    /// Persists `records`; the in-memory state is only replaced after this succeeds.
    private func save(_ records: [MCPEventSubscriptionKey: MCPEventSubscription]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = records.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The file holds webhook signing secrets: create the temporary file
        // private from the start, then move it into place, so it is never
        // readable by others, not even briefly.
        let temporary = directory.appendingPathComponent(".\(fileURL.lastPathComponent).\(UUID().uuidString).tmp")
        guard FileManager.default.createFile(
            atPath: temporary.path,
            contents: try encoder.encode(sorted),
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw CocoaError(.fileWriteUnknown)
        }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                _ = try FileManager.default.replaceItemAt(fileURL, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: fileURL)
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}
