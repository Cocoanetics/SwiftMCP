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
    
    /// The label of the parameter (e.g., "for" in "for subject: String")
    public let label: String
    
    /// The type of the parameter
    public let type: String
    
    /// An optional description of the parameter
    public let description: String?
    
    /// An optional default value for the parameter
    public let defaultValue: Sendable?
    
    /// The possible values for enum parameters
    public let enumValues: [String]?
    
    /// Whether the parameter is required (no default value)
    public let isRequired: Bool
    
    /**
     Creates a new parameter info with the specified name, type, description, and default value.
     
     - Parameters:
       - name: The name of the parameter
       - label: The label of the parameter (e.g., "for" in "for subject: String")
       - type: The type of the parameter
       - description: An optional description of the parameter
       - defaultValue: An optional default value for the parameter
       - enumValues: The possible values if this is an enum parameter
     */
    public init(name: String, label: String, type: String, description: String? = nil, defaultValue: Sendable? = nil, enumValues: [String]? = nil) {
        self.name = name
        self.label = label
        self.type = type
        self.description = description
        self.defaultValue = defaultValue
        self.enumValues = enumValues
        self.isRequired = defaultValue == nil
    }
} 
