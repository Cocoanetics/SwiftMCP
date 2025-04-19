//
//  JSONSchema.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// A simplified representation of JSON Schema for use in the macros
public indirect enum JSONSchema: Sendable {
	/**
	 A structured schema type
	 */
	public struct Object: Sendable
	{
		/// The properties of the type
		var properties: [String: JSONSchema]
		
		/// Which if the properties are mandatory
		var required: [String] = []
		
		/// Description of the type
		var description: String? = nil
		
		/// Whether additional properties are allowed
		var additionalProperties: Bool? = false
	}
	
	/// A string schema
    case string(description: String? = nil, format: String? = nil)
    
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
