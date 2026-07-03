import Foundation

/// Information about a function parameter
public struct MCPParameterInfo: Sendable {
    /// The name of the parameter
    public let name: String

    /// The type of the parameter
    public let type: Sendable.Type

    /// An optional description of the parameter
    public let description: String?

    /// An optional default value for the parameter
    public let defaultValue: Sendable?

    /// Whether the parameter is required (no default value)
    public let isRequired: Bool

    /// Whether modern (`2026-07-28`) clients should mirror this parameter into an
    /// `Mcp-Param-{name}` HTTP header (the `x-mcp-header` inputSchema annotation),
    /// declared via `@MCPTool(headerParameters:)`.
    public let isMirroredToHeader: Bool

    /// Whether the parameter is optional (has a default value)
    public var isOptional: Bool {
        return !isRequired
    }

/**
     Creates a new parameter info with the specified name, type, description, and default value.

     - Parameters:
       - name: The name of the parameter
       - type: The type of the parameter
       - description: An optional description of the parameter
       - defaultValue: An optional default value for the parameter
       - isRequired: Whether the parameter is required (no default value)
       - isMirroredToHeader: Whether modern clients mirror the parameter into an
         `Mcp-Param-{name}` header (`x-mcp-header`)
     */
    public init(
        name: String,
        type: Sendable.Type,
        description: String? = nil,
        defaultValue: Sendable? = nil,
        isRequired: Bool,
        isMirroredToHeader: Bool = false
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
        self.isRequired = isRequired
        self.isMirroredToHeader = isMirroredToHeader
    }
}
