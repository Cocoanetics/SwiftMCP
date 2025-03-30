//
//  SchemaPropertyInfo.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 30.03.25.
//


import Foundation

/// Information about a function parameter
public struct SchemaPropertyInfo: Sendable {
    /// The name of the parameter
    public let name: String
    
    /// The type of the parameter
    public let type: String
    
    /// The actual type of the parameter (e.g. Address.self)
    public let schemaType: Any.Type?
    
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
       - type: The type of the parameter
       - schemaType: The actual type of the parameter (e.g. Address.self)
       - description: An optional description of the parameter
       - defaultValue: An optional default value for the parameter
       - enumValues: The possible values if this is an enum parameter
     */
    public init(name: String, type: String, schemaType: Any.Type? = nil, description: String? = nil, defaultValue: Sendable? = nil, enumValues: [String]? = nil, isRequired: Bool) {
        self.name = name
        self.type = type
        self.schemaType = schemaType
        self.description = description
        self.defaultValue = defaultValue
        self.enumValues = enumValues
        self.isRequired = isRequired
    }
} 
