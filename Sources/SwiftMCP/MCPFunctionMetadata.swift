//
//  MCPFunctionMetadata.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/**
 * Represents metadata for a function in the Model Context Protocol (MCP).
 *
 * This struct holds information about a function, including its name,
 * parameters, return type, and description. It is used to generate
 * JSON schema representations of functions for AI models.
 */
public struct MCPFunctionMetadata: Sendable {
    // MARK: - Properties
    
    /// The name of the function
    public let name: String
    
    /// The parameters of the function
    public let parameters: [ParameterInfo]
    
    /// The return type of the function, if any
    public let returnType: String?
    
    /// An optional description of the function's purpose
    public let description: String?
    
    // MARK: - Initialization
    
    /**
     * Creates a new MCPFunctionMetadata instance.
     *
     * - Parameters:
     *   - name: The name of the function
     *   - parameters: The parameters of the function
     *   - returnType: The return type of the function, if any
     *   - description: An optional description of the function's purpose
     */
    public init(name: String, parameters: [ParameterInfo], returnType: String?, description: String? = nil) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.description = description
    }
} 