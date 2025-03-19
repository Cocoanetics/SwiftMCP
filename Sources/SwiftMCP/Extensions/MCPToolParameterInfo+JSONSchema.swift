//
//  MCPToolParameterInfo+JSONSchema.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation

extension MCPToolParameterInfo {
	
	var jsonSchema: JSONSchema {
		
		switch type.JSONSchemaType {
				
			case "array":
				
				// This is an array type
				let elementType: JSONSchema
				if let arrayElementType = type.arrayElementType {
					if arrayElementType.JSONSchemaType == "number" {
						elementType = JSONSchema.number()
					} else if arrayElementType.JSONSchemaType == "boolean" {
						elementType = JSONSchema.boolean()
					} else {
						elementType = JSONSchema.string()
					}
				} else {
					elementType = JSONSchema.string()
				}
				
				return JSONSchema.array(items: elementType, description: description)
				
			case "number":
				
				return JSONSchema.number(description: description)
				
			case "boolean":
				
				return JSONSchema.boolean(description: description)
				
			default:
				
				return JSONSchema.string(description: description)
		}
	}
}
