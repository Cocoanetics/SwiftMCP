import Foundation

/// Information about a resource function parameter
public struct MCPResourceParameterInfo: Sendable {
    /// The name of the parameter
    public let name: String
    
    /// The type of the parameter
    public let type: Any.Type
    
    /// Whether the parameter is optional (has a default value)
    public let isOptional: Bool
    
    /// The default value of the parameter as a string representation
    public let defaultValue: String?
    
    /// A description of the parameter
    public let description: String?
    
    /**
     Creates a new MCPResourceParameterInfo instance.
     
     - Parameters:
       - name: The name of the parameter
       - type: The type of the parameter
       - description: A description of the parameter
       - isOptional: Whether the parameter is optional
       - defaultValue: The default value of the parameter as a string
     */
    public init(
        name: String,
        type: Any.Type,
        description: String? = nil,
        isOptional: Bool = false,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.description = description
        self.isOptional = isOptional
        self.defaultValue = defaultValue
    }
} 