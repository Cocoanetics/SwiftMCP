//
//  MCPToolMetadata.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// Metadata about a tool function
public struct MCPToolMetadata: Sendable {
    /// The common function metadata
    public let functionMetadata: MCPFunctionMetadata
    
    /// A description of what the function returns
    public let returnTypeDescription: String?
    
    /// Whether the function's actions are consequential (defaults to true)
    public let isConsequential: Bool
    
    /**
     Creates a new MCPToolMetadata instance.
     
     - Parameters:
       - name: The name of the function
       - description: A description of the function's purpose
       - parameters: The parameters of the function
       - returnType: The return type of the function, if any
       - returnTypeDescription: A description of what the function returns
       - isAsync: Whether the function is asynchronous
       - isThrowing: Whether the function can throw errors
       - isConsequential: Whether the function's actions are consequential
     */
    public init(
        name: String,
        description: String? = nil,
        parameters: [MCPParameterInfo],
        returnType: Sendable.Type? = nil,
        returnTypeDescription: String? = nil,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        isConsequential: Bool = true
    ) {
        self.functionMetadata = MCPFunctionMetadata(
            name: name,
            description: description,
            parameters: parameters,
            returnType: returnType,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
        self.returnTypeDescription = returnTypeDescription
        self.isConsequential = isConsequential
    }
    
    // Convenience accessors for common properties
    public var name: String { functionMetadata.name }
    public var description: String? { functionMetadata.description }
    public var parameters: [MCPParameterInfo] { functionMetadata.parameters }
    public var returnType: Sendable.Type? { functionMetadata.returnType }
    public var isAsync: Bool { functionMetadata.isAsync }
    public var isThrowing: Bool { functionMetadata.isThrowing }
    
    /// Enriches a dictionary of arguments with default values and throws if a required parameter is missing
    public func enrichArguments(_ arguments: [String: Sendable]) throws -> [String: Sendable] {
        return try functionMetadata.enrichArguments(arguments)
    }
} 
