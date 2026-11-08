import Foundation

// MARK: - events/list (modern only, MCP Events)
extension MCPServer {

    /// Whether this server declares at least one event.
    internal func serverDeclaresEvents() async -> Bool {
        guard let provider = self as? MCPEventProviding else { return false }
        return !(await provider.mcpEventMetadata).isEmpty
    }

    /// Handles `events/list`. Events are a `2026-07-28` feature: a request that
    /// is not on a modern revision is answered as an unknown method.
    internal func handleEventsList(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage {
        guard let profile = await RequestContext.current?.modernProfile, profile.has(.events) else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32601, message: "Method not found")
            )
        }

        let metadata = await (self as? MCPEventProviding)?.mcpEventMetadata ?? []
        let result = EventsListResult(events: metadata.map(\.descriptor))
        do {
            return JSONRPCMessage.response(id: request.id, result: .object(try JSONDictionary(encoding: result)))
        } catch {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32603, message: "Internal error: \(error.localizedDescription)")
            )
        }
    }
}

#if Server
import Crypto

// MARK: - events/subscribe and events/unsubscribe (modern only, webhook delivery)
extension MCPServer {

    /// Stable digest under which a principal is stored, so a bearer token never
    /// reaches the store or its file.
    public static func eventPrincipalDigest(_ principal: String) -> String {
        "sha256:" + SHA256.hash(data: Data(principal.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Revocation hook: drops every webhook subscription owned by `principal`
    /// (for example after its token was revoked) and returns the removed records.
    @discardableResult
    public func revokeEventSubscriptions(forPrincipal principal: String) async throws -> [MCPEventSubscription] {
        guard let provider = self as? MCPEventProviding else { return [] }
        return try await provider.eventSubscriptionStore.revoke(principal: Self.eventPrincipalDigest(principal))
    }

    /// The caller's stored principal, or `nil` when the request is unauthenticated.
    /// An anonymous caller has no identity to bind a subscription to, and the
    /// compound key is guessable, so it could remove or overwrite another's.
    private func eventsPrincipal() async -> String? {
        let principal = await MCPTaskPrincipal.current().rawValue
        return principal == "anonymous" ? nil : Self.eventPrincipalDigest(principal)
    }

    private func eventsError(_ id: JSONRPCID?, _ code: Int, _ message: String) -> JSONRPCMessage {
        JSONRPCMessage.errorResponse(id: id, error: .init(code: code, message: message))
    }

    /// Resolves the provider when the request is on a modern revision with events.
    private func eventsProvider(for request: JSONRPCMessage.JSONRPCRequestData) async -> (any MCPEventProviding)? {
        guard let profile = await RequestContext.current?.modernProfile, profile.has(.events),
              let provider = self as? MCPEventProviding,
              await serverDeclaresEvents() else { return nil }
        return provider
    }

    /// Describes why `params` is not an acceptable subscription, or `nil` if it is.
    private func validateSubscribe(_ params: EventsSubscribeParams, provider: any MCPEventProviding) async -> String? {
        guard let event = await provider.mcpEventMetadata.first(where: { $0.name == params.name }) else {
            return "Unknown event: \(params.name)"
        }
        guard (params.delivery.mode ?? "webhook") == "webhook", event.delivery?.contains("webhook") ?? true else {
            return "Event \(params.name) does not support webhook delivery"
        }
        do {
            try EventFilterValidator.validate(params.arguments, against: event.descriptor.inputSchema)
        } catch {
            return "Invalid filter: \(error)"
        }
        do {
            try provider.eventDeliveryConfiguration.urlPolicy.validate(params.delivery.url)
        } catch {
            return "Invalid webhook URL: \(error)"
        }
        guard let secret = params.delivery.secret, (try? WebhookSigner(secret: secret)) != nil else {
            return "Invalid or missing webhook secret"
        }
        return nil
    }

    /// Handles `events/subscribe`: creates or refreshes the caller's webhook
    /// subscription. Delivery itself is not implemented yet.
    internal func handleEventsSubscribe(
        _ request: JSONRPCMessage.JSONRPCRequestData,
        now: Date = Date()
    ) async -> JSONRPCMessage {
        guard let provider = await eventsProvider(for: request) else {
            return eventsError(request.id, -32601, "Method not found")
        }
        guard let principal = await eventsPrincipal() else {
            return eventsError(request.id, -32600, "Event subscriptions require an authenticated caller")
        }
        guard let params = try? request.params?.decoded(EventsSubscribeParams.self) else {
            return eventsError(request.id, -32602, "Invalid params")
        }
        if let problem = await validateSubscribe(params, provider: provider) {
            return eventsError(request.id, -32602, problem)
        }
        guard let secret = params.delivery.secret else {
            return eventsError(request.id, -32602, "Invalid or missing webhook secret")
        }

        let maxTTL = provider.eventSubscriptionMaxTTL
        var ttl = maxTTL
        if let ttlMs = params.ttlMs {
            guard ttlMs > 0 else { return eventsError(request.id, -32602, "ttlMs must be positive") }
            ttl = min(maxTTL, Double(ttlMs) / 1000)
        }
        let expiresAt = now.addingTimeInterval(ttl)

        let subscription = MCPEventSubscription(
            principal: principal,
            name: params.name,
            arguments: params.arguments,
            url: params.delivery.url,
            secret: secret,
            createdAt: now,
            expiresAt: expiresAt,
            cursor: params.cursor
        )
        do {
            let stored = try await provider.eventSubscriptionStore.upsert(subscription, now: now)
            let result = EventsSubscribeResult(
                id: stored.subscription.id,
                refreshBefore: ISO8601DateFormatter().string(from: stored.subscription.expiresAt ?? expiresAt),
                cursor: stored.subscription.cursor,
                deliveryStatus: stored.created ? nil : .init(active: true)
            )
            return JSONRPCMessage.response(id: request.id, result: .object(try JSONDictionary(encoding: result)))
        } catch {
            return eventsError(request.id, -32603, "Internal error: \(error.localizedDescription)")
        }
    }

    /// Handles `events/unsubscribe`. Idempotent, and scoped to the caller's own
    /// subscriptions: an unknown or foreign key succeeds without effect.
    internal func handleEventsUnsubscribe(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage {
        guard let provider = await eventsProvider(for: request) else {
            return eventsError(request.id, -32601, "Method not found")
        }
        guard let principal = await eventsPrincipal() else {
            return eventsError(request.id, -32600, "Event subscriptions require an authenticated caller")
        }
        guard let params = try? request.params?.decoded(EventsUnsubscribeParams.self) else {
            return eventsError(request.id, -32602, "Invalid params")
        }
        let key = MCPEventSubscriptionKey(
            principal: principal,
            name: params.name,
            arguments: params.arguments,
            url: params.delivery.url
        )
        do {
            try await provider.eventSubscriptionStore.remove(key: key)
            return JSONRPCMessage.response(
                id: request.id,
                result: .object(try JSONDictionary(encoding: EventsUnsubscribeResult()))
            )
        } catch {
            return eventsError(request.id, -32603, "Internal error: \(error.localizedDescription)")
        }
    }
}

#else
extension MCPServer {
    /// Webhook subscriptions need the `Server` trait (signing and URL policy).
    internal func handleEventsSubscribe(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage {
        JSONRPCMessage.errorResponse(id: request.id, error: .init(code: -32601, message: "Method not found"))
    }

    internal func handleEventsUnsubscribe(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage {
        JSONRPCMessage.errorResponse(id: request.id, error: .init(code: -32601, message: "Method not found"))
    }
}
#endif
