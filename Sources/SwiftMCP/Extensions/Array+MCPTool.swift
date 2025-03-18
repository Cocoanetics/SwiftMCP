//
//  Array+MCPTool.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

extension Array where Element == MCPToolMetadata {
    public func convertedToTools() -> [MCPTool] {
        return self.map { meta in
            // Create properties for the JSON schema
            let properties = Dictionary(uniqueKeysWithValues: meta.parameters.map { param in

				return (param.name, param.jsonSchema)
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
