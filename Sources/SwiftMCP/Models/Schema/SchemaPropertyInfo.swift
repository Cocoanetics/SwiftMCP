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
    
    /// The actual type of the parameter (e.g. Address.self)
    public let schemaType: Any.Type
    
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
    public init(name: String, schemaType: Any.Type, description: String? = nil, defaultValue: Sendable? = nil, isRequired: Bool) {
        self.name = name
        self.schemaType = schemaType
        self.description = description
        self.defaultValue = defaultValue
        self.isRequired = isRequired
    }
    
    /// Converts this property info to a JSON Schema representation
    public var schema: JSONSchema {
        // If this is a SchemaRepresentable type, use its schema
        if let schemaType = schemaType as? any SchemaRepresentable.Type {
            return schemaType.schema
        }
        
        // If this is a CaseIterable type, return a string schema with enum values
        if let caseIterableType = schemaType as? any CaseIterable.Type {
            return JSONSchema.string(description: description, enumValues: caseIterableType.caseLabels)
        }
        
        // If this is a JSONSchemaTypeConvertible type, use its schema
        if let convertibleType = schemaType as? any JSONSchemaTypeConvertible.Type {
            return convertibleType.jsonSchema(description: description)
        }
        
        // Default to string for unknown types
        return JSONSchema.string(description: description)
    }

    public var jsonSchema: JSONSchema {
        return schema
    }
}
