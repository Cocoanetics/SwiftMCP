import Foundation

/// Metadata about a resource function
public struct MCPResourceMetadata: Sendable {
    /// The URI template of the resource
    public let uriTemplate: String
    
    /// The name of the function
    public let name: String
    
    /// A description of the resource
    public let description: String?
    
    /// The parameters of the function
    public let parameters: [MCPResourceParameterInfo]
    
    /// The return type of the function, if any
    public let returnType: Any.Type?
    
    /// Whether the function is asynchronous
    public let isAsync: Bool
    
    /// Whether the function can throw errors
    public let isThrowing: Bool
    
    /// The MIME type of the resource (optional)
    public let mimeType: String?
    
    /**
     Creates a new MCPResourceMetadata instance.
     
     - Parameters:
       - uriTemplate: The URI template of the resource
       - name: The name of the function
       - description: A description of the resource
       - parameters: The parameters of the function
       - returnType: The return type of the function, if any
       - isAsync: Whether the function is asynchronous
       - isThrowing: Whether the function can throw errors
       - mimeType: The MIME type of the resource
     */
    public init(
        uriTemplate: String,
        name: String,
        description: String? = nil,
        parameters: [MCPResourceParameterInfo],
        returnType: Any.Type? = nil,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        mimeType: String? = nil
    ) {
        self.uriTemplate = uriTemplate
        self.name = name
        self.description = description
        self.parameters = parameters
        self.returnType = returnType
        self.isAsync = isAsync
        self.isThrowing = isThrowing
        self.mimeType = mimeType
    }
    
    /// Converts metadata to MCPResourceTemplate
    public func toResourceTemplate() -> SimpleResourceTemplate {
        SimpleResourceTemplate(
            uriTemplate: uriTemplate,
            name: name,
            description: description,
            mimeType: mimeType
        )
    }
}

/// Simple implementation of MCPResourceTemplate
public struct SimpleResourceTemplate: MCPResourceTemplate {
    public let uriTemplate: String
    public let name: String
    public let description: String?
    public let mimeType: String?
} 