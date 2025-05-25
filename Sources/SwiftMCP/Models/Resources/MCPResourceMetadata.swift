import Foundation

/// Metadata about a resource function
public struct MCPResourceMetadata: Sendable {
    /// The common function metadata
    public let functionMetadata: MCPFunctionMetadata
    
    /// The URI template of the resource
    public let uriTemplate: String
    
    /// The name of the function (for internal dispatching)
    public let functionName: String
    
    /// The MIME type of the resource (optional)
    public let mimeType: String?
    
    /**
     Creates a new MCPResourceMetadata instance.
     
     - Parameters:
       - uriTemplate: The URI template of the resource
       - functionName: The name of the function (for dispatching)
       - name: The display name of the resource
       - description: A description of the resource
       - parameters: The parameters of the function
       - returnType: The return type of the function, if any
       - isAsync: Whether the function is asynchronous
       - isThrowing: Whether the function can throw errors
       - mimeType: The MIME type of the resource
     */
    public init(
        uriTemplate: String,
        functionName: String,
        name: String,
        description: String? = nil,
        parameters: [MCPParameterInfo],
        returnType: Sendable.Type? = nil,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        mimeType: String? = nil
    ) {
        self.functionMetadata = MCPFunctionMetadata(
            name: name,
            description: description,
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
        self.uriTemplate = uriTemplate
        self.functionName = functionName
        self.mimeType = mimeType
    }
    
    // Convenience accessors for common properties
    public var name: String { functionMetadata.name }
    public var description: String? { functionMetadata.description }
    public var parameters: [MCPParameterInfo] { functionMetadata.parameters }
    public var returnType: Sendable.Type? { functionMetadata.returnType }
    public var isAsync: Bool { functionMetadata.isAsync }
    public var isThrowing: Bool { functionMetadata.isThrowing }
    
    /// Converts metadata to MCPResourceTemplate
    public func toResourceTemplate() -> SimpleResourceTemplate {
        SimpleResourceTemplate(
            uriTemplate: uriTemplate,
            name: name,
            description: description,
            mimeType: mimeType
        )
    }
    
    /// Enriches a dictionary of arguments with default values and throws if a required parameter is missing
    public func enrichArguments(_ arguments: [String: Sendable]) throws -> [String: Sendable] {
        return try functionMetadata.enrichArguments(arguments)
    }
}

/// Simple implementation of MCPResourceTemplate
public struct SimpleResourceTemplate: MCPResourceTemplate {
    public let uriTemplate: String
    public let name: String
    public let description: String?
    public let mimeType: String?
} 