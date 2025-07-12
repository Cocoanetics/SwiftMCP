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
        public var properties: [String: JSONSchema]

        /// Which if the properties are mandatory
        public var required: [String] = []

        /// Title of the type
        public var title: String? = nil

        /// Description of the type
        public var description: String? = nil

        /// Whether additional properties are allowed
        public var additionalProperties: Bool? = false

        /// public initializer
        public init(properties: [String : JSONSchema], required: [String], title: String? = nil, description: String? = nil, additionalProperties: Bool? = nil) {
            self.properties = properties
            self.required = required
            self.title = title
            self.description = description
            self.additionalProperties = additionalProperties
        }
    }

    /// A string schema
    case string(title: String? = nil, description: String? = nil, format: String? = nil, minLength: Int? = nil, maxLength: Int? = nil)

    /// A number schema
    case number(title: String? = nil, description: String? = nil, minimum: Double? = nil, maximum: Double? = nil)

    /// A boolean schema
    case boolean(title: String? = nil, description: String? = nil, default: Bool? = nil)

    /// An array schema
    case array(items: JSONSchema, title: String? = nil, description: String? = nil)

    /// An object schema
    case object(Object)

    /// An enum schema with possible values
    case `enum`(values: [String], title: String? = nil, description: String? = nil, enumNames: [String]? = nil)
}

// Extension to remove required fields from a schema
extension JSONSchema {
    /// Returns a new schema with all required fields removed
    public var withoutRequired: JSONSchema {
        switch self {
            case .object(let object):
                // For object schemas, create a new object with empty required array
                return .object(Object(properties: object.properties.mapValues { $0.withoutRequired },
									  required: [],
									  description: object.description,
									  additionalProperties: object.additionalProperties))

            case .array(let items, let title, let description):
                // For array schemas, recursively apply to items
                return .array(items: items.withoutRequired, title: title, description: description)

            // For other schema types, return as is since they don't have required fields
            case .string, .number, .boolean, .enum:
                return self
        }
    }
}

// Extension to add additionalProperties:false to all objects, for use with structured results
extension JSONSchema {
    /// Returns a new schema with all required fields removed
    public var addingAdditionalPropertiesRestrictionToObjects: JSONSchema {
        switch self {
            case .object(let object):
                return .object(Object(properties: object.properties.mapValues { $0.addingAdditionalPropertiesRestrictionToObjects },
									  required: object.required,
									  description: object.description,
									  additionalProperties: false))

            case .array(let items, let title, let description):
                // For array schemas, recursively apply to items
                return .array(items: items.addingAdditionalPropertiesRestrictionToObjects, title: title, description: description)

            // For other schema types, return as is since they don't have required fields
            default:
                return self
        }
    }
}

