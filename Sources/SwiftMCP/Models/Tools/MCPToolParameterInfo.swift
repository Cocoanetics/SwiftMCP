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
    
    /// The actual type of the parameter (e.g. Address.self)
    public let type: Any.Type
    
    /// An optional description of the parameter
    public let description: String?
    
    /// An optional default value for the parameter
    public let defaultValue: Sendable?
    
    /// Whether the parameter is required (no default value)
    public let isRequired: Bool
    
    /**
     Creates a new parameter info with the specified name, type, description, and default value.
     
     - Parameters:
       - name: The name of the parameter
       - schemaType: The actual type of the parameter (e.g. Address.self)
       - description: An optional description of the parameter
       - defaultValue: An optional default value for the parameter
     */
    public init(name: String, type: Any.Type, description: String? = nil, defaultValue: Sendable? = nil, isRequired: Bool) {
        self.name = name
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
        self.isRequired = isRequired
    }
} 
