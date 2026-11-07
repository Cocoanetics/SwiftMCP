import Foundation

/// Protocol for servers that declare event types (`@MCPEvent`) to clients.
public protocol MCPEventProviding {
    /// Metadata for all declared events, including `@MCPExtension` contributions.
    ///
    /// Not declared `nonisolated` so actor-backed conformers can satisfy this
    /// requirement with an actor-isolated property.
    var mcpEventMetadata: [MCPEventMetadata] { get async }

    /// Where `events/subscribe` subscriptions are kept. Defaults to an
    /// in-memory store private to this server; return an ``MCPFileEventSubscriptionStore`` to persist.
    var eventSubscriptionStore: any MCPEventSubscriptionStore { get }

    /// Longest lifetime granted to a subscription, and the one used when the
    /// subscriber suggests none. Subscribers must refresh before it lapses.
    var eventSubscriptionMaxTTL: TimeInterval { get }
}

extension MCPEventProviding {
    public var eventSubscriptionStore: any MCPEventSubscriptionStore {
        MCPDefaultEventStoreRegistry.shared.store(for: self)
    }

    public var eventSubscriptionMaxTTL: TimeInterval { 3600 }

    public var mcpEventMetadata: [MCPEventMetadata] {
        get async { [] }
    }
}
