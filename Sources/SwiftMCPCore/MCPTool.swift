//
//  MCPTool.swift
//  SwiftMCPCore
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// Represents a tool that can be used by an AI model
public struct MCPTool: Sendable {
    /// The name of the tool
    public let name: String
    
    /// An optional description of the tool
    public let description: String?
    
    /// The JSON schema defining the tool's input parameters
    public let inputSchema: JSONSchema
    
    /**
     Creates a new tool with the specified name, description, and input schema.
     
     - Parameters:
       - name: The name of the tool
       - description: An optional description of the tool
       - inputSchema: The schema defining the function's input parameters
     */
    public init(name: String, description: String? = nil, inputSchema: JSONSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
} 