/// Protocol for types that expose MCP function metadata via a registry.
public protocol MCPFunctionRegistryProviding {
    /// Metadata associated with the conforming type.
    static var metadata: MCPFunctionRegistry.TypeMetadata { get }
}
