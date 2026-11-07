//
//  MCPEventsExtension.swift
//  SwiftMCP
//
//  Wire constants for MCP Events (subscriber-driven, webhook delivery), a
//  `2026-07-28` (modern era) feature. Phase 0 of #204: models only — nothing
//  is advertised or handled yet.
//

import Foundation

/// Constants for the MCP Events feature.
public enum MCPEventsExtension {
    /// Key under which a server advertises Events in its capabilities.
    public static let capabilityKey = "events"

    /// Method name of the event-type listing request.
    public static let listMethod = "events/list"

    /// Method name of the webhook subscription request.
    public static let subscribeMethod = "events/subscribe"

    /// Method name of the webhook unsubscription request.
    public static let unsubscribeMethod = "events/unsubscribe"
}

/// Header names of the Standard Webhooks signing scheme used for event delivery.
///
/// See <https://www.standardwebhooks.com>.
public enum StandardWebhooksHeader {
    /// Unique message id, stable across delivery retries.
    public static let id = "webhook-id"

    /// Unix timestamp (seconds) of the delivery attempt.
    public static let timestamp = "webhook-timestamp"

    /// Space-delimited, version-prefixed signature(s), e.g. `v1,<base64>`.
    public static let signature = "webhook-signature"

    /// MCP-specific (not Standard Webhooks) header carrying the subscription `id`,
    /// so the receiver can pick the right secret before parsing the body.
    public static let subscriptionId = "X-MCP-Subscription-Id"
}
