//
//  Array+MCPTool.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

extension Array where Element == MCPToolMetadata {
    /// Converts tool metadata into wire `MCPTool`s.
    ///
    /// - Parameter includeOutputSchema: When `false`, the `outputSchema` field
    ///   is omitted — structured tool output was introduced in `2025-06-18`, so
    ///   it must not be advertised to clients negotiating an earlier revision.
    public func convertedToTools(includeOutputSchema: Bool = true) -> [MCPTool] {
        return self.map { meta in
            // Create properties for the JSON schema
            let properties = Dictionary(uniqueKeysWithValues: meta.parameters.map { param in
                return (param.name, param.schema)
            })

            // Determine which parameters are required using the isRequired property
            let required = meta.parameters.filter { $0.isRequired }.map { $0.name }

            // Create the input schema
            let hasParameters = !properties.isEmpty
            let inputSchema = JSONSchema.object(JSONSchema.Object(
                properties: properties,
                required: required,
                description: hasParameters ? meta.description : nil,
                additionalProperties: hasParameters ? nil : false
            ))
            let outputSchema = includeOutputSchema ? meta.outputSchema : nil

            // Create and return the tool
            return MCPTool(
                name: meta.name,
                description: meta.description,
                inputSchema: inputSchema,
                outputSchema: outputSchema,
                annotations: meta.annotations
            )
        }
    }
}
