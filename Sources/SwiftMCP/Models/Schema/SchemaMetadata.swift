//
//  MCPToolMetadata.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 30.03.25.
//


import Foundation

/// Metadata about a SchemaRepresentable struct
public struct SchemaMetadata: Sendable {
    /// The name of the function
    public let name: String
    
    /// The parameters of the function
    public let parameters: [MCPToolParameterInfo]
    
    /// A description of the function's purpose
    public let description: String?
    
    /**
     Creates a new MCPToolMetadata instance.
     
     - Parameters:
       - name: The name of the function
       - description: A description of the function's purpose
       - parameters: The parameters of the function
     */
    public init(name: String, description: String? = nil, parameters: [MCPToolParameterInfo]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
} 
