//
//  MCPToolParameterInfo+JSONSchema.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation

// Extension to get element type from array type
extension Array {
	static var elementType: Any.Type? {
		return Element.self
	}
}

extension MCPToolParameterInfo {
	
	var jsonSchema: JSONSchema {
		// If this is a SchemaRepresentable type, use its schema
		if let schemaType = type as? any SchemaRepresentable.Type {
			return schemaType.schema
		}
		
		// If this is a CaseIterable type, return a string schema with enum values
		if let caseIterableType = type as? any CaseIterable.Type {
			return JSONSchema.string(description: description, enumValues: caseIterableType.caseLabels)
		}
		
		// Handle array types
		if let arrayType = type as? Array<Sendable>.Type {
			// Get the element type from the array
			let schema: JSONSchema
			if let type = arrayType.elementType {
				if type == Int.self || type == Double.self {
					schema = JSONSchema.number()
				} else if type == Bool.self {
					schema = JSONSchema.boolean()
				} else if let schemaType = type as? any SchemaRepresentable.Type {
					schema = schemaType.schema
				} else {
					schema = JSONSchema.string()
				}
			} else {
				schema = JSONSchema.string()
			}
			return JSONSchema.array(items: schema, description: description)
		}
		
		// Handle basic types
		switch type {
		case is Int.Type, is Double.Type:
			return JSONSchema.number(description: description)
		case is Bool.Type:
			return JSONSchema.boolean(description: description)
		default:
			return JSONSchema.string(description: description)
		}
	}
}
