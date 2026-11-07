import Foundation

/// Protocol for servers that declare event types (`@MCPEvent`) to clients.
public protocol MCPEventProviding {
    /// Metadata for all declared events, including `@MCPExtension` contributions.
    ///
    /// Not declared `nonisolated` so actor-backed conformers can satisfy this
    /// requirement with an actor-isolated property.
    var mcpEventMetadata: [MCPEventMetadata] { get async }
}

extension MCPEventProviding {
    public var mcpEventMetadata: [MCPEventMetadata] {
        get async { [] }
    }
}
