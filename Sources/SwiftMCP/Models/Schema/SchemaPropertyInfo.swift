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
    
    /// Converts this property info to a JSON Schema representation
    public var schema: JSONSchema {
        // If this is an enum parameter, return a string schema with enum values
        if let enumValues = enumValues {
            return .string(description: description, enumValues: enumValues)
        }
        
        // Handle array types
        if type.hasPrefix("[") && type.hasSuffix("]") {
            let elementType = String(type.dropFirst().dropLast())
            let baseElementType = elementType.hasSuffix("?") || elementType.hasSuffix("!") ? String(elementType.dropLast()) : elementType
            
            // If the element type is SchemaRepresentable, use its schema
            if let elementSchemaType = schemaType as? any SchemaRepresentable.Type {
                return .array(items: elementSchemaType.schema, description: description)
            }
            
            // Handle basic array types
            let elementSchema: JSONSchema
            switch baseElementType {
            case "Int", "Double", "Float":
                elementSchema = .number()
            case "Bool":
                elementSchema = .boolean()
            default:
                // For unknown types, try to get the schema type
                if let schemaType = schemaType as? any SchemaRepresentable.Type {
                    elementSchema = schemaType.schema
                } else {
                    elementSchema = .string()
                }
            }
            
            return .array(items: elementSchema, description: description)
        }
        
        // If this is a nested schema type, get its schema
        if let schemaType = schemaType as? any SchemaRepresentable.Type {
            return schemaType.schema
        }
        
        // Handle basic types
        switch type {
        case "String":
            return .string(description: description)
        case "Int", "Double", "Float":
            return .number(description: description)
        case "Bool":
            return .boolean(description: description)
        default:
            // For unknown types, try to get the schema type
            if let schemaType = schemaType as? any SchemaRepresentable.Type {
                return schemaType.schema
            } else {
                return .string(description: description)
            }
        }
    }
}

/// Extension to provide schema support for arrays of SchemaRepresentable elements
extension Array: SchemaRepresentable where Element: SchemaRepresentable {
	public static var __schemaMetadata: SchemaMetadata {
		return .init(name: "", parameters: [])
	}
	
    public static var schema: JSONSchema {
        .array(items: Element.schema)
    }
} 
