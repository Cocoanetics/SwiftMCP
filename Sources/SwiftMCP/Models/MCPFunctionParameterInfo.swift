//
//  MCPFunctionParameterInfo.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/**
 Represents information about a function parameter in the Model Context Protocol (MCP).

 This struct holds details about a parameter, including its name, type,
 description, and default value. It is used to generate JSON schema
 representations of function parameters for AI models.
 */
public struct MCPFunctionParameterInfo: Sendable {
    // MARK: - Properties
    
    /// The name of the parameter
    public let name: String
    
    /// The type of the parameter
    public let type: String
    
    /// An optional description of the parameter
    public let description: String?
    
    /// An optional default value for the parameter
    public let defaultValue: String?
    
    // MARK: - Initialization
    
    /**
     Creates a new ParameterInfo instance.

     - Parameters:
       - name: The name of the parameter
       - type: The type of the parameter
       - description: An optional description of the parameter
       - defaultValue: An optional default value for the parameter
     */
    public init(name: String, type: String, description: String? = nil, defaultValue: Any? = nil) {
        self.name = name
        self.type = type
        self.description = description
        // Convert defaultValue to String if it's not nil
        if let value = defaultValue {
            if let stringValue = value as? String {
                // Add quotes for string values
                self.defaultValue = "\"\(stringValue)\""
            } else {
                self.defaultValue = String(describing: value)
            }
        } else {
            self.defaultValue = nil
        }
    }
} 
