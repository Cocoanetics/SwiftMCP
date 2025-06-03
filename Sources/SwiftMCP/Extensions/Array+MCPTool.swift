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
        return (param.name, param.schema)
    })

// Determine which parameters are required using the isRequired property
        let required = meta.parameters.filter { $0.isRequired }.map { $0.name }

// Create the input schema
        let inputSchema = JSONSchema.object(JSONSchema.Object(
                properties: properties,
                required: required,
                description: meta.description
            ))

// Create and return the tool
        return MCPTool(
                name: meta.name,
                description: meta.description,
                inputSchema: inputSchema
            )
    }
    }
} 
