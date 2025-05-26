import Foundation

/// Metadata about a resource function
public struct MCPResourceMetadata: Sendable {
    /// The common function metadata
    public let functionMetadata: MCPFunctionMetadata
    
    /// The URI templates of the resource
    public let uriTemplates: Set<String>
    
    /// The display name of the resource
    public let name: String
    
    /// The MIME type of the resource (optional)
    public let mimeType: String?
    
    /**
     Creates a new MCPResourceMetadata instance.
     
     - Parameters:
       - uriTemplates: The URI templates of the resource
       - name: The display name of the resource (overrides function name if different)
       - functionName: The name of the function (for dispatching)
       - description: A description of the resource
       - parameters: The parameters of the function
       - returnType: The return type of the function, if any
       - returnTypeDescription: A description of what the function returns
       - isAsync: Whether the function is asynchronous
       - isThrowing: Whether the function can throw errors
       - mimeType: The MIME type of the resource
     */
    public init(
        uriTemplates: Set<String>,
        name: String? = nil,
        functionName: String,
        description: String? = nil,
        parameters: [MCPParameterInfo],
        returnType: Sendable.Type? = nil,
        returnTypeDescription: String? = nil,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        mimeType: String? = nil
    ) {
        self.name = name ?? functionName
        self.functionMetadata = MCPFunctionMetadata(
            name: functionName,
            description: description,
            parameters: parameters,
            returnType: returnType,
            returnTypeDescription: returnTypeDescription,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
        self.uriTemplates = uriTemplates
        self.mimeType = mimeType
    }
    
    // Convenience accessors for common properties
    public var description: String? { functionMetadata.description }
    public var parameters: [MCPParameterInfo] { functionMetadata.parameters }
    public var returnType: Sendable.Type? { functionMetadata.returnType }
    public var returnTypeDescription: String? { functionMetadata.returnTypeDescription }
    public var isAsync: Bool { functionMetadata.isAsync }
    public var isThrowing: Bool { functionMetadata.isThrowing }
    
    /// Converts metadata to MCPResourceTemplate array (one for each URI template)
    public func toResourceTemplates() -> [SimpleResourceTemplate] {
        return uriTemplates.map { template in
            SimpleResourceTemplate(
                uriTemplate: template,
                name: name,
                description: description,
                mimeType: mimeType
            )
        }
    }
    
    /// Enriches a dictionary of arguments with default values and throws if a required parameter is missing
    public func enrichArguments(_ arguments: [String: Sendable]) throws -> [String: Sendable] {
        return try functionMetadata.enrichArguments(arguments)
    }
    
    /// Finds the best matching URI template for a given URL
    /// Returns the template that matches the most parameters
    public func bestMatchingTemplate(for url: URL) -> String? {
        var bestTemplate: String?
        var maxParameterCount = -1
        
        for template in uriTemplates {
            if let variables = url.extractTemplateVariables(from: template) {
                let parameterCount = variables.count
                if parameterCount > maxParameterCount {
                    maxParameterCount = parameterCount
                    bestTemplate = template
                }
            }
        }
        
        return bestTemplate
    }
}

/// Simple implementation of MCPResourceTemplate
public struct SimpleResourceTemplate: MCPResourceTemplate {
    public let uriTemplate: String
    public let name: String
    public let description: String?
    public let mimeType: String?
} 