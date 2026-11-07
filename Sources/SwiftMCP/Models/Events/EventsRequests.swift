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

/// Params of `events/subscribe` (webhook delivery).
public struct EventsSubscribeParams: Codable, Sendable, Equatable {
    /// Event type name, as listed by `events/list`.
    public let name: String

    /// Filter conforming to the event's `inputSchema`.
    public let arguments: JSONValue?

    /// URL the server POSTs signed event deliveries to.
    public let callbackUrl: String

    /// Subscriber-chosen identity; resubscribing with the same id renews the subscription.
    public let subscriptionId: String?

    /// Subscriber-supplied secret for Standard Webhooks signing.
    public let secret: String?

    public init(
        name: String,
        arguments: JSONValue? = nil,
        callbackUrl: String,
        subscriptionId: String? = nil,
        secret: String? = nil
    ) {
        self.name = name
        self.arguments = arguments
        self.callbackUrl = callbackUrl
        self.subscriptionId = subscriptionId
        self.secret = secret
    }
}

/// Result of `events/subscribe`.
public struct EventsSubscribeResult: Codable, Sendable, Equatable {
    /// Identity of the (new or renewed) subscription.
    public let subscriptionId: String

    /// ISO 8601 time at which the subscription lapses unless renewed.
    public let expiresAt: String?

    /// Suggested interval, in milliseconds, after which to renew.
    public let renewAfterMs: Int?

    public init(subscriptionId: String, expiresAt: String? = nil, renewAfterMs: Int? = nil) {
        self.subscriptionId = subscriptionId
        self.expiresAt = expiresAt
        self.renewAfterMs = renewAfterMs
    }
}

/// Params of `events/unsubscribe`.
public struct EventsUnsubscribeParams: Codable, Sendable, Equatable {
    public let subscriptionId: String

    public init(subscriptionId: String) {
        self.subscriptionId = subscriptionId
    }
}

/// Result of `events/unsubscribe` (empty object).
public struct EventsUnsubscribeResult: Codable, Sendable, Equatable {
    public init() {}
}
