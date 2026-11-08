#if Client
import Foundation

extension MCPServerProxy {
    /// Lists event types the server advertises (`events/list`).
    ///
    /// Events are a modern-era (`2026-07-28`) feature. Throws when the
    /// negotiated protocol era does not support them.
    public func listEvents(cursor: String? = nil) async throws -> EventsListResult {
        try requireEventsSupport()
        var params: JSONDictionary = [:]
        if let cursor {
            params["cursor"] = .string(cursor)
        }
        return try await requestResult(
            method: MCPEventsExtension.listMethod,
            params: params.isEmpty ? nil : params,
            as: EventsListResult.self
        )
    }

    /// Creates or refreshes a webhook subscription (`events/subscribe`).
    ///
    /// The caller must be authenticated (for example via ``meta`` `accessToken`);
    /// anonymous sessions are rejected by the server. Throws when the negotiated
    /// protocol era does not support Events.
    public func subscribeEvent(
        name: String,
        arguments: JSONValue = .object([:]),
        delivery: EventsWebhookDelivery,
        cursor: String? = nil,
        maxAgeMs: Int? = nil,
        ttlMs: Int? = nil
    ) async throws -> EventsSubscribeResult {
        try requireEventsSupport()
        let params = try JSONDictionary(encoding: EventsSubscribeParams(
            name: name,
            arguments: arguments,
            delivery: delivery,
            cursor: cursor,
            maxAgeMs: maxAgeMs,
            ttlMs: ttlMs
        ))
        return try await requestResult(
            method: MCPEventsExtension.subscribeMethod,
            params: params,
            as: EventsSubscribeResult.self
        )
    }

    /// Removes a webhook subscription (`events/unsubscribe`).
    ///
    /// Idempotent: an unknown or foreign key succeeds without effect. Throws when
    /// the negotiated protocol era does not support Events.
    public func unsubscribeEvent(
        name: String,
        arguments: JSONValue = .object([:]),
        delivery: EventsWebhookDelivery
    ) async throws {
        try requireEventsSupport()
        let params = try JSONDictionary(encoding: EventsUnsubscribeParams(
            name: name,
            arguments: arguments,
            delivery: delivery
        ))
        _ = try await requestResult(
            method: MCPEventsExtension.unsubscribeMethod,
            params: params,
            as: EventsUnsubscribeResult.self
        )
    }

    /// Events require a negotiated modern revision whose profile includes
    /// ``MCPFeature/events``. Legacy connections fail here before a request is sent.
    private func requireEventsSupport() throws {
        guard negotiatedEra == .modern,
              let version = modernProtocolVersion,
              MCPProtocolVersion.profile(for: version)?.has(.events) == true else {
            throw MCPServerProxyError.communicationError(
                "Events require a negotiated modern protocol revision that supports them"
            )
        }
    }
}
#endif
