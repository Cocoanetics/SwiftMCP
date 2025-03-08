//
//  Array+MCPTool.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

extension Array where Element == MCPFunctionMetadata {
    public func convertedToTools() -> [MCPTool] {
        return self.map { meta in
            // Create properties for the JSON schema
            let properties = Dictionary(uniqueKeysWithValues: meta.parameters.map { param in
                // Create the appropriate schema based on the parameter type
                let schema: JSONSchema
                let jsonSchemaType = param.type.JSONSchemaType
                
                if jsonSchemaType == "array" {
                    // This is an array type
                    let elementType: JSONSchema
                    if let arrayElementType = param.type.arrayElementType {
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
                    schema = JSONSchema.array(items: elementType, description: param.description)
                } else if jsonSchemaType == "number" {
                    schema = JSONSchema.number(description: param.description)
                } else if jsonSchemaType == "boolean" {
                    schema = JSONSchema.boolean(description: param.description)
                } else {
                    schema = JSONSchema.string(description: param.description)
                }
                
                return (param.name, schema)
            })
            
            // Determine which parameters are required (those without default values)
            let required = meta.parameters.filter { $0.defaultValue == nil }.map { $0.name }
            
            // Create the input schema
            let inputSchema = JSONSchema.object(
                properties: properties,
                required: required,
                description: meta.description
            )
            
            // Create and return the tool
            return MCPTool(
                name: meta.name,
                description: meta.description,
                inputSchema: inputSchema
            )
        }
    }
} 
