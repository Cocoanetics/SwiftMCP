//
//  MCPToolMetadata.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 30.03.25.
//


import Foundation

/// Metadata about a SchemaRepresentable struct
public struct SchemaMetadata: Sendable {
    /// The name of the type
    public let name: String

    /// The parameters of the function
    public let parameters: [SchemaPropertyInfo]

    /// A description of the function's purpose
    public let description: String?

/**
     Creates a new MCPToolMetadata instance.
     
     - Parameters:
       - name: The name of the function
       - description: A description of the function's purpose
       - parameters: The parameters of the function
     */
    public init(name: String, description: String? = nil, parameters: [SchemaPropertyInfo]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }

    /// Converts this schema metadata to a JSON Schema representation
    public var schema: JSONSchema {
        // Convert parameters to properties
        var properties: [String: JSONSchema] = [:]
        var required: [String] = []

        for param in parameters {
            let schema = param.schema
            properties[param.name] = schema

            if param.isRequired {
                required.append(param.name)
            }
        }

        return .object(JSONSchema.Object(
			properties: properties,
			required: required,
			description: description
		))
    }
} 
