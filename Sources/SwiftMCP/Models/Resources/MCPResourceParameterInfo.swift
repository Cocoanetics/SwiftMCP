import Foundation

/// Information about a resource function parameter
public struct MCPResourceParameterInfo: Sendable {
    /// The name of the parameter
    public let name: String
    
    /// The type of the parameter
    public let type: Sendable.Type
    
    /// A description of the parameter
    public let description: String?
    
    /// An optional default value for the parameter
    public let defaultValue: Sendable?
    
    /// Whether the parameter is optional (has a default value)
    public let isOptional: Bool
    
    /**
     Creates a new MCPResourceParameterInfo instance.
     
     - Parameters:
       - name: The name of the parameter
       - type: The type of the parameter
       - description: A description of the parameter
       - defaultValue: The default value of the parameter
       - isOptional: Whether the parameter is optional
     */
    public init(
        name: String,
        type: Sendable.Type,
        description: String? = nil,
        defaultValue: Sendable? = nil,
        isOptional: Bool = false
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
        self.isOptional = isOptional
    }
} 