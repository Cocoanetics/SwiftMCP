//
//  MCPEventSubscriptionStore.swift
//  SwiftMCP
//
//  Persistence boundary for `events/subscribe` webhook subscriptions, with an
//  in-memory default and a JSON-file implementation. Phase 2 of #204: the
//  subscribe/unsubscribe lifecycle only, no delivery yet.
//

import Foundation

/// Outcome of ``MCPEventSubscriptionStore/upsert(_:now:)``.
public typealias MCPEventUpsertResult = (subscription: MCPEventSubscription, created: Bool)

/// One webhook subscription created by `events/subscribe`.
///
/// Identity is the compound key (`principal`, `name`, `arguments`, `url`), so a
/// repeated subscribe with the same key refreshes the existing record and keeps
/// its `id`.
public struct MCPEventSubscription: Codable, Sendable, Equatable {
    /// Server-derived routing handle, stable for the lifetime of the record.
    public let id: String

    /// The authorization principal that owns the subscription.
    public let principal: String

    /// Event type name.
    public let name: String

    /// Validated subscriber filter.
    public let arguments: JSONValue

    /// Webhook callback URL.
    public let url: String

    /// Signing secret (`whsec_` + base64).
    public var secret: String

    public let createdAt: Date

    /// Time of the last subscribe/refresh.
    public var refreshedAt: Date

    /// Time after which the subscription lapses; `nil` for no expiry.
    public var expiresAt: Date?

    /// Replay watermark supplied by the subscriber, if any.
    public var cursor: String?

    public init(
        id: String = "sub_" + UUID().uuidString.lowercased(),
        principal: String,
        name: String,
        arguments: JSONValue,
        url: String,
        secret: String,
        createdAt: Date = Date(),
        refreshedAt: Date? = nil,
        expiresAt: Date? = nil,
        cursor: String? = nil
    ) {
        self.id = id
        self.principal = principal
        self.name = name
        self.arguments = arguments
        self.url = url
        self.secret = secret
        self.createdAt = createdAt
        self.refreshedAt = refreshedAt ?? createdAt
        self.expiresAt = expiresAt
        self.cursor = cursor
    }

    /// Whether the subscription has lapsed at `date`.
    public func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }

    /// Canonical identity of the compound key; argument key order does not matter.
    public var key: MCPEventSubscriptionKey {
        MCPEventSubscriptionKey(principal: principal, name: name, arguments: arguments, url: url)
    }
}

/// Compound key identifying a subscription: (principal, name, arguments, URL).
public struct MCPEventSubscriptionKey: Hashable, Sendable {
    public let principal: String
    public let name: String
    public let url: String

    /// Canonical (sorted-key) JSON of the filter arguments.
    private let canonicalArguments: String

    public init(principal: String, name: String, arguments: JSONValue, url: String) {
        self.principal = principal
        self.name = name
        self.url = url
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        self.canonicalArguments = (try? encoder.encode(arguments)).flatMap {
            String(data: $0, encoding: .utf8)
        } ?? ""
    }
}

/// Stores webhook subscriptions. Implementations must be safe for concurrent
/// use (typically actors).
///
/// Expired records are never returned: every read takes the current time and
/// treats lapsed records as absent.
public protocol MCPEventSubscriptionStore: Sendable {
    /// Creates the subscription, or refreshes the existing record with the same
    /// key (keeping its `id` and `createdAt`). Returns the stored record and
    /// whether it was newly created. A lapsed record with the same key is
    /// replaced by a new one.
    func upsert(_ subscription: MCPEventSubscription, now: Date) async throws -> MCPEventUpsertResult

    /// The active subscription with `id`, regardless of owner (for delivery).
    func subscription(id: String, now: Date) async throws -> MCPEventSubscription?

    /// Active subscriptions, optionally restricted to one principal.
    func subscriptions(principal: String?, now: Date) async throws -> [MCPEventSubscription]

    /// Removes the subscription with exactly this key; `true` if one was removed.
    @discardableResult
    func remove(key: MCPEventSubscriptionKey) async throws -> Bool

    /// Revocation hook: removes every subscription owned by `principal` (for
    /// example when its token is revoked) and returns the removed records.
    @discardableResult
    func revoke(principal: String) async throws -> [MCPEventSubscription]

    /// Drops lapsed records and returns them.
    @discardableResult
    func purgeExpired(now: Date) async throws -> [MCPEventSubscription]
}

/// Default store: subscriptions live in memory and are lost on restart.
public actor MCPInMemoryEventSubscriptionStore: MCPEventSubscriptionStore {
    /// Shared default instance used by servers that do not supply a store.
    public static let shared = MCPInMemoryEventSubscriptionStore()

    private var records: [MCPEventSubscriptionKey: MCPEventSubscription] = [:]

    public init() {}

    public func upsert(
        _ subscription: MCPEventSubscription,
        now: Date
    ) async throws -> MCPEventUpsertResult {
        let result = Self.merge(subscription, into: records[subscription.key], now: now)
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
        return (refreshed, false)
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
        var updated = records
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

    /// Persists `records`; the in-memory state is only replaced after this succeeds.
    private func save(_ records: [MCPEventSubscriptionKey: MCPEventSubscription]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let sorted = records.values.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(sorted).write(to: fileURL, options: .atomic)
        // The file holds webhook signing secrets.
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
