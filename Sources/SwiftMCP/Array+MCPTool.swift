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
			var properties: [String: MCPTool.JSONSchema.Property] = [:]
			var required: [String] = []

			for parameter in meta.parameters {
				let jsonSchemaType = parameter.type.JSONSchemaType

				if jsonSchemaType == "array", let elementType = parameter.type.arrayElementType {
					let itemsProperty = MCPTool.JSONSchema.Property(type: elementType.JSONSchemaType)
					properties[parameter.name] = MCPTool.JSONSchema.Property(type: "array", items: itemsProperty)
				} else {
					properties[parameter.name] = MCPTool.JSONSchema.Property(type: jsonSchemaType)
				}

				required.append(parameter.name)
			}

			let schema = MCPTool.JSONSchema(
				type: "object",
				properties: properties.isEmpty ? nil : properties,
				required: required.isEmpty ? nil : required
			)

			return MCPTool(name: meta.name, description: meta.description, inputSchema: schema)
		}
	}
}
