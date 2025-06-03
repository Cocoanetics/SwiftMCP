import Foundation

/// Common metadata about a function (tool or resource)
public struct MCPFunctionMetadata: Sendable {
/// The name of the function
    public let name: String

/// A description of the function's purpose
    public let description: String?

/// The parameters of the function
    public let parameters: [MCPParameterInfo]

/// The return type of the function, if any
    public let returnType: Sendable.Type?

/// A description of what the function returns
    public let returnTypeDescription: String?

/// Whether the function is asynchronous
    public let isAsync: Bool

/// Whether the function can throw errors
    public let isThrowing: Bool

/**
     Creates a new MCPFunctionMetadata instance.
     
     - Parameters:
       - name: The name of the function
       - description: A description of the function's purpose
       - parameters: The parameters of the function
       - returnType: The return type of the function, if any
       - returnTypeDescription: A description of what the function returns
       - isAsync: Whether the function is asynchronous
       - isThrowing: Whether the function can throw errors
     */
    public init(
        name: String,
        description: String? = nil,
        parameters: [MCPParameterInfo],
        returnType: Sendable.Type? = nil,
        returnTypeDescription: String? = nil,
        isAsync: Bool = false,
        isThrowing: Bool = false
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.returnType = returnType
        self.returnTypeDescription = returnTypeDescription
        self.isAsync = isAsync
        self.isThrowing = isThrowing
    }

/// Enriches a dictionary of arguments with default values and throws if a required parameter is missing
    public func enrichArguments(_ arguments: [String: Sendable]) throws -> [String: Sendable] {
        var enrichedArguments = arguments
        for param in parameters {
            if enrichedArguments[param.name] == nil {
                if let defaultValue = param.defaultValue {
                    enrichedArguments[param.name] = defaultValue
                } else if param.isRequired {
                        throw MCPToolError.missingRequiredParameter(parameterName: param.name)
                    }
            }
        }
        return enrichedArguments
    }
} 