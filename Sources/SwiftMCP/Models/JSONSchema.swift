//
//  JSONSchema.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// A simplified representation of JSON Schema for use in the macros
public indirect enum JSONSchema: Sendable {
    /// A string schema
    case string(description: String? = nil, format: String? = nil, enumValues: [String]? = nil)
    
    /// A number schema
    case number(description: String? = nil)
    
    /// A boolean schema
    case boolean(description: String? = nil)
    
    /// An array schema
    case array(items: JSONSchema, description: String? = nil)
    
    /// An object schema
	case object(Object)
    
    /// An enum schema with possible values
    case `enum`(values: [String], description: String? = nil)
	
	public struct Object: Sendable
	{
		var properties: [String: JSONSchema]
		var required: [String] = []
		var description: String? = nil
		var additionalProperties: Bool? = false
	}
}

// Extension to remove required fields from a schema
extension JSONSchema {
    /// Returns a new schema with all required fields removed
    var withoutRequired: JSONSchema {
        switch self {
        case .object(let object):
            // For object schemas, create a new object with empty required array
				return .object(Object(properties: object.properties,
									  required: [],
									  description: object.description,
									  additionalProperties: object.additionalProperties))
            
        case .array(let items, let description):
            // For array schemas, recursively apply to items
            return .array(items: items.withoutRequired, description: description)
            
        // For other schema types, return as is since they don't have required fields
        case .string, .number, .boolean, .enum:
            return self
        }
    }
} 
