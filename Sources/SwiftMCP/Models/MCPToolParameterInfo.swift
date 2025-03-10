//
//  MCPToolParameterInfo.swift
//  SwiftMCPCore
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// Information about a function parameter
public struct MCPToolParameterInfo: Sendable {
    /// The name of the parameter
    public let name: String
    
    /// The type of the parameter
    public let type: String
    
    /// An optional description of the parameter
    public let description: String?
    
    /// An optional default value for the parameter
    public let defaultValue: String?
    
    /**
     Creates a new parameter info with the specified name, type, description, and default value.
     
     - Parameters:
       - name: The name of the parameter
       - type: The type of the parameter
       - description: An optional description of the parameter
       - defaultValue: An optional default value for the parameter
     */
    public init(name: String, type: String, description: String? = nil, defaultValue: String? = nil) {
        self.name = name
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
    }
} 
