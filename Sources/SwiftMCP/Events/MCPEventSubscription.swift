//
//  MCPEventSubscription.swift
//  SwiftMCP
//
//  Webhook subscription record, compound key and delivery-state updates.
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

    /// Digest of the authorization principal that owns the subscription (see
    /// ``MCPServer/eventPrincipalDigest(_:)``); the raw principal can be a bearer
    /// token and is never stored.
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

    /// Whether webhook delivery is enabled. Exhausted transient failures can
    /// clear this; a subscribe refresh restores it. 410/413 refusals leave it set.
    public var isDeliveryActive: Bool

    /// Exhausted `.failed` deliveries since the last success or refresh.
    public var consecutiveDeliveryFailures: Int

    /// Time of the last delivery attempt that produced a definitive outcome.
    public var lastDeliveryAt: Date?

    /// Error text of the last failed or rejected delivery, if any.
    public var lastDeliveryError: String?

    /// When the current run of consecutive failures began.
    public var failedSince: Date?

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
        cursor: String? = nil,
        isDeliveryActive: Bool = true,
        consecutiveDeliveryFailures: Int = 0,
        lastDeliveryAt: Date? = nil,
        lastDeliveryError: String? = nil,
        failedSince: Date? = nil
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
        self.isDeliveryActive = isDeliveryActive
        self.consecutiveDeliveryFailures = consecutiveDeliveryFailures
        self.lastDeliveryAt = lastDeliveryAt
        self.lastDeliveryError = lastDeliveryError
        self.failedSince = failedSince
    }

    private enum CodingKeys: String, CodingKey {
        case id, principal, name, arguments, url, secret
        case createdAt, refreshedAt, expiresAt, cursor
        case isDeliveryActive, consecutiveDeliveryFailures
        case lastDeliveryAt, lastDeliveryError, failedSince
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        principal = try container.decode(String.self, forKey: .principal)
        name = try container.decode(String.self, forKey: .name)
        arguments = try container.decode(JSONValue.self, forKey: .arguments)
        url = try container.decode(String.self, forKey: .url)
        secret = try container.decode(String.self, forKey: .secret)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        refreshedAt = try container.decode(Date.self, forKey: .refreshedAt)
        expiresAt = try container.decodeIfPresent(Date.self, forKey: .expiresAt)
        cursor = try container.decodeIfPresent(String.self, forKey: .cursor)
        // Older store files predate delivery-state fields; treat them as active.
        isDeliveryActive = try container.decodeIfPresent(Bool.self, forKey: .isDeliveryActive) ?? true
        consecutiveDeliveryFailures =
            try container.decodeIfPresent(Int.self, forKey: .consecutiveDeliveryFailures) ?? 0
        lastDeliveryAt = try container.decodeIfPresent(Date.self, forKey: .lastDeliveryAt)
        lastDeliveryError = try container.decodeIfPresent(String.self, forKey: .lastDeliveryError)
        failedSince = try container.decodeIfPresent(Date.self, forKey: .failedSince)
    }

    /// Whether the subscription has lapsed at `date`.
    public func isExpired(at date: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= date
    }

    /// Whether delivery may start for this record at `date`.
    public func isDeliverable(at date: Date) -> Bool {
        isDeliveryActive && !isExpired(at: date)
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

/// How a finished delivery updates a subscription's failure/active state.
public enum MCPEventSubscriptionDeliveryUpdate: Sendable, Equatable {
    case delivered
    /// Permanent refusal of this delivery (for example 410 or 413); subscription stays.
    case rejected(error: String?)
    /// Exhausted transient failure of this delivery.
    case failed(error: String?)
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

    /// Records a finished delivery against the subscription's failure/active state.
    /// Exhausted failures accumulate toward auto-disable; a success clears the
    /// failure run; a rejection (including 410/413) keeps the subscription
    /// active. Returns the updated record, or `nil` if it is gone.
    @discardableResult
    func applyDeliveryOutcome(
        id: String,
        update: MCPEventSubscriptionDeliveryUpdate,
        now: Date,
        disableAfterConsecutiveFailures: Int
    ) async throws -> MCPEventSubscription?
}
