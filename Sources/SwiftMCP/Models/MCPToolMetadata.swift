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
    
    /// An optional description of the function
    public let description: String?
    
    /**
     Creates a new tool metadata with the specified name, parameters, return type, and description.
     
     - Parameters:
       - name: The name of the function
       - parameters: The parameters of the function
       - returnType: The return type of the function, if any
       - description: An optional description of the function's purpose
     */
    public init(name: String, parameters: [MCPToolParameterInfo], returnType: String? = nil, description: String? = nil) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.description = description
    }
} 
