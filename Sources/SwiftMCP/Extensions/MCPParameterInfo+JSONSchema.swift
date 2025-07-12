//
//  MCPParameterInfo+JSONSchema.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation

protocol ArraySchemaBridge {
    static var elementType: Any.Type { get }
}

extension Array: ArraySchemaBridge {
    static var elementType: Any.Type { Element.self }
}

extension MCPParameterInfo {

    public var schema: JSONSchema {
        // If this is a SchemaRepresentable type, use its schema
        if let schemaType = type as? any SchemaRepresentable.Type {
            return schemaType.schemaMetadata.schema
        }

        // If this is a CaseIterable type, return a string schema with enum values
        if let caseIterableType = type as? any CaseIterable.Type {
            return JSONSchema.enum(values: caseIterableType.caseLabels, description: description)
        }

        // Handle array types
        if let arrayType = type as? ArrayWithSchemaRepresentableElements.Type {

            return arrayType.schema(description: description)
        }

        if let arrayType = type as? ArrayWithCaseIterableElements.Type {

            return arrayType.schema(description: description)
        }

        if let arrayBridge = type as? ArraySchemaBridge.Type {
            // Get the element type from the array
            let type = arrayBridge.elementType

            let schema: JSONSchema

            if type == Int.self || type == Double.self {
                schema = JSONSchema.number(title: nil, description: nil, minimum: nil, maximum: nil)
            } else if type == Bool.self {
                schema = JSONSchema.boolean(title: nil, description: nil, default: nil)
            } else if let schemaType = type as? any SchemaRepresentable.Type {
                schema = schemaType.schemaMetadata.schema
            } else {
                schema = JSONSchema.string(title: nil, description: nil, format: nil, minLength: nil, maxLength: nil)
            }

            return JSONSchema.array(items: schema, description: description)
        }

        // Handle basic types
        switch type {
            case is Int.Type, is Double.Type:
                return JSONSchema.number(title: nil, description: description, minimum: nil, maximum: nil)
            case is Bool.Type:
                return JSONSchema.boolean(title: nil, description: description, default: nil)
            default:
                return JSONSchema.string(title: nil, description: description, format: nil, minLength: nil, maxLength: nil)
        }
    }
}
