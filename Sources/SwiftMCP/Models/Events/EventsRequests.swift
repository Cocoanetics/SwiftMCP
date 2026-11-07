//
//  EventsRequests.swift
//  SwiftMCP
//
//  Params and results for `events/list`, `events/subscribe` and
//  `events/unsubscribe`.
//

import Foundation

/// Params of `events/list`.
public struct EventsListParams: Codable, Sendable, Equatable {
    /// Pagination cursor from a previous result's `nextCursor`.
    public let cursor: String?

    public init(cursor: String? = nil) {
        self.cursor = cursor
    }
}

/// Result of `events/list`.
public struct EventsListResult: Codable, Sendable, Equatable {
    public let events: [EventDescriptor]

    /// Cursor for the next page, absent on the last page.
    public let nextCursor: String?

    public init(events: [EventDescriptor], nextCursor: String? = nil) {
        self.events = events
        self.nextCursor = nextCursor
    }
}

/// Webhook delivery target of `events/subscribe` and `events/unsubscribe`.
public struct EventsWebhookDelivery: Codable, Sendable, Equatable {
    /// Delivery mode; `"webhook"` for webhook delivery.
    public let mode: String?

    /// HTTPS URL the server POSTs signed event deliveries to.
    public let url: String

    /// Signing secret (`whsec_` + base64). Sent on subscribe, omitted on unsubscribe.
    public let secret: String?

    public init(mode: String? = "webhook", url: String, secret: String? = nil) {
        self.mode = mode
        self.url = url
        self.secret = secret
    }
}

/// Params of `events/subscribe` (webhook delivery). A repeated subscribe with
/// the same name, arguments and URL refreshes the existing subscription.
public struct EventsSubscribeParams: Codable, Sendable, Equatable {
    /// Event type name, as listed by `events/list`.
    public let name: String

    /// Filter conforming to the event's `inputSchema`.
    public let arguments: JSONValue

    public let delivery: EventsWebhookDelivery

    /// Replay watermark from a previous result; absent or `null` starts fresh.
    public let cursor: String?

    /// Replay floor in milliseconds.
    public let maxAgeMs: Int?

    /// Suggested subscription TTL in milliseconds.
    public let ttlMs: Int?

    public init(
        name: String,
        arguments: JSONValue = .object([:]),
        delivery: EventsWebhookDelivery,
        cursor: String? = nil,
        maxAgeMs: Int? = nil,
        ttlMs: Int? = nil
    ) {
        self.name = name
        self.arguments = arguments
        self.delivery = delivery
        self.cursor = cursor
        self.maxAgeMs = maxAgeMs
        self.ttlMs = ttlMs
    }
}

/// Result of `events/subscribe`.
public struct EventsSubscribeResult: Codable, Sendable, Equatable {
    /// Status of webhook deliveries, present on refresh.
    public struct DeliveryStatus: Codable, Sendable, Equatable {
        public let active: Bool
        public let lastDeliveryAt: String?
        public let lastError: String?
        public let failedSince: String?
        public let throttled: Bool?
        public let retryAfterMs: Int?

        public init(
            active: Bool,
            lastDeliveryAt: String? = nil,
            lastError: String? = nil,
            failedSince: String? = nil,
            throttled: Bool? = nil,
            retryAfterMs: Int? = nil
        ) {
            self.active = active
            self.lastDeliveryAt = lastDeliveryAt
            self.lastError = lastError
            self.failedSince = failedSince
            self.throttled = throttled
            self.retryAfterMs = retryAfterMs
        }
    }

    /// Server-derived routing handle (sent back as `X-MCP-Subscription-Id`).
    public let id: String

    /// ISO 8601 time the subscription must be refreshed before; `nil` for no expiry.
    public let refreshBefore: String?

    /// Safe-to-persist replay watermark.
    public let cursor: String?

    /// `true` if delivery starts later than the supplied cursor.
    public let truncated: Bool?

    public let deliveryStatus: DeliveryStatus?

    public init(
        id: String,
        refreshBefore: String? = nil,
        cursor: String? = nil,
        truncated: Bool? = nil,
        deliveryStatus: DeliveryStatus? = nil
    ) {
        self.id = id
        self.refreshBefore = refreshBefore
        self.cursor = cursor
        self.truncated = truncated
        self.deliveryStatus = deliveryStatus
    }
}

/// Params of `events/unsubscribe`: the compound key (name, arguments, URL) used
/// by subscribe. The server-derived id is not accepted as input.
public struct EventsUnsubscribeParams: Codable, Sendable, Equatable {
    public let name: String
    public let arguments: JSONValue
    public let delivery: EventsWebhookDelivery

    public init(name: String, arguments: JSONValue = .object([:]), delivery: EventsWebhookDelivery) {
        self.name = name
        self.arguments = arguments
        self.delivery = delivery
    }
}

/// Result of `events/unsubscribe` (empty object).
public struct EventsUnsubscribeResult: Codable, Sendable, Equatable {
    public init() {}
}
