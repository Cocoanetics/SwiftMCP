import Foundation

/// Registry for MCP function metadata associated with a specific server type.
public enum MCPFunctionRegistry {
    private struct MetadataStore<Value> {
        var storage: [String: Value] = [:]
        var order: [String] = []

        mutating func register(_ metadata: Value, named name: String) {
            if storage[name] == nil {
                order.append(name)
            }
            storage[name] = metadata
        }

        func allMetadata() -> [Value] {
            order.compactMap { storage[$0] }
        }

        func metadata(named name: String) -> Value? {
            storage[name]
        }
    }

    private struct RegistryStorage {
        var toolMetadata: [ObjectIdentifier: MetadataStore<MCPToolMetadata>] = [:]
        var resourceMetadata: [ObjectIdentifier: MetadataStore<MCPResourceMetadata>] = [:]
        var promptMetadata: [ObjectIdentifier: MetadataStore<MCPPromptMetadata>] = [:]
    }

    private final class CriticalState<State>: @unchecked Sendable {
        private let lock = NSLock()
        private var state: State

        init(_ state: State) {
            self.state = state
        }

        func withCriticalRegion<T>(_ body: (inout State) -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body(&state)
        }
    }

    private static let storage = CriticalState(RegistryStorage())

    public static func registerTool(_ metadata: MCPToolMetadata, named name: String, for type: Any.Type) {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            var store = state.toolMetadata[identifier] ?? MetadataStore()
            store.register(metadata, named: name)
            state.toolMetadata[identifier] = store
        }
    }

    public static func registerResource(_ metadata: MCPResourceMetadata, named name: String, for type: Any.Type) {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            var store = state.resourceMetadata[identifier] ?? MetadataStore()
            store.register(metadata, named: name)
            state.resourceMetadata[identifier] = store
        }
    }

    public static func registerPrompt(_ metadata: MCPPromptMetadata, named name: String, for type: Any.Type) {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            var store = state.promptMetadata[identifier] ?? MetadataStore()
            store.register(metadata, named: name)
            state.promptMetadata[identifier] = store
        }
    }

    public static func toolMetadata(for type: Any.Type) -> [MCPToolMetadata] {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            return state.toolMetadata[identifier]?.allMetadata() ?? []
        }
    }

    public static func resourceMetadata(for type: Any.Type) -> [MCPResourceMetadata] {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            return state.resourceMetadata[identifier]?.allMetadata() ?? []
        }
    }

    public static func promptMetadata(for type: Any.Type) -> [MCPPromptMetadata] {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            return state.promptMetadata[identifier]?.allMetadata() ?? []
        }
    }

    public static func toolMetadata(for type: Any.Type, named name: String) -> MCPToolMetadata? {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            return state.toolMetadata[identifier]?.metadata(named: name)
        }
    }

    public static func resourceMetadata(for type: Any.Type, named name: String) -> MCPResourceMetadata? {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            return state.resourceMetadata[identifier]?.metadata(named: name)
        }
    }

    public static func promptMetadata(for type: Any.Type, named name: String) -> MCPPromptMetadata? {
        storage.withCriticalRegion { state in
            let identifier = ObjectIdentifier(type)
            return state.promptMetadata[identifier]?.metadata(named: name)
        }
    }

    /// Convenience wrapper around the registry for a single type.
    public struct TypeMetadata {
        fileprivate let type: Any.Type

        /// All tool metadata registered for this type.
        public var tools: [MCPToolMetadata] {
            MCPFunctionRegistry.toolMetadata(for: type)
        }

        /// All resource metadata registered for this type.
        public var resources: [MCPResourceMetadata] {
            MCPFunctionRegistry.resourceMetadata(for: type)
        }

        /// All prompt metadata registered for this type.
        public var prompts: [MCPPromptMetadata] {
            MCPFunctionRegistry.promptMetadata(for: type)
        }

        /// Retrieves tool metadata for the specified name.
        public func tool(named name: String) -> MCPToolMetadata? {
            MCPFunctionRegistry.toolMetadata(for: type, named: name)
        }

        /// Retrieves resource metadata for the specified name.
        public func resource(named name: String) -> MCPResourceMetadata? {
            MCPFunctionRegistry.resourceMetadata(for: type, named: name)
        }

        /// Retrieves prompt metadata for the specified name.
        public func prompt(named name: String) -> MCPPromptMetadata? {
            MCPFunctionRegistry.promptMetadata(for: type, named: name)
        }
    }

    /// Returns a metadata proxy for the provided type.
    public static func metadata(for type: Any.Type) -> TypeMetadata {
        TypeMetadata(type: type)
    }
}
