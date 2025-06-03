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
     */
    public init(name: String, type: Sendable.Type, description: String? = nil, defaultValue: Sendable? = nil, isRequired: Bool) {
        self.name = name
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
        self.isRequired = isRequired
    }
} 