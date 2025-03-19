//
//  MCPToolMetadata.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// Metadata about a tool function
public struct MCPToolMetadata: Sendable {
    /// The name of the function
    public let name: String
    
    /// The parameters of the function
    public let parameters: [MCPToolParameterInfo]
    
    /// The return type of the function, if any
    public let returnType: String?
    
    /// A description of what the function returns
    public let returnTypeDescription: String?
    
    /// Whether the function is asynchronous
    public let isAsync: Bool
    
    /// Whether the function can throw errors
    public let isThrowing: Bool
    
    /// A description of the function's purpose
    public let description: String?
    
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
     */
    public init(name: String, description: String? = nil, parameters: [MCPToolParameterInfo], returnType: String? = nil, returnTypeDescription: String? = nil, isAsync: Bool = false, isThrowing: Bool = false) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.returnType = returnType
        self.returnTypeDescription = returnTypeDescription
        self.isAsync = isAsync
        self.isThrowing = isThrowing
    }
} 
