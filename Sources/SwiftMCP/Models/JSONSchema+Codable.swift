//
//  JSONSchema+Codable.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 19.04.25.
//

import Foundation

/// Coding keys for `JSONSchema` encoding and decoding, shared across the
/// per-file extensions that implement `Codable`.
internal enum JSONSchemaCodingKeys: String, CodingKey {
    /// The type of the schema (string, number, boolean, array, or object)
    case type
    /// The properties of an object schema
    case properties
    /// The required properties of an object schema
    case required
    /// A title for the schema
    case title
    /// A description of the schema
    case description
    /// The schema for array items
    case items
    /// The possible values for an enum schema
    case enumValues = "enum"
    /// Display names for enum values
    case enumNames
    /// The format of the content
    case format
    /// Minimum length for string values
    case minLength
    /// Maximum length for string values
    case maxLength
    /// Minimum value for numeric types
    case minimum
    /// Maximum value for numeric types
    case maximum
    /// Default value for boolean types
    case `default`
    /// If additional properties are allowed (optional, needed for structured responses, not for MCP)
    case additionalProperties
    /// The possible schemas for a union
    case oneOf
    /// Alternative union key used by some servers
    case anyOf
}

/**
 Extension to make JSONSchema conform to Codable
 */
extension JSONSchema: Codable {
    /// Local alias keeping the `CodingKeys` name available inside the extension body.
    fileprivate typealias CodingKeys = JSONSchemaCodingKeys

    /**
     Creates a new JSONSchema instance by decoding from the given decoder.

     - Parameter decoder: The decoder to read data from
     - Throws: DecodingError if the data is corrupted or if an unsupported schema type is encountered
     */
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let description = try container.decodeIfPresent(String.self, forKey: .description)

        if let union = try Self.decodeUnionSchema(
            from: container,
            title: title,
            description: description
        ) {
            self = union
            return
        }

        let type = Self.resolveSchemaType(from: container)

        switch type {
        case "string":
            self = try Self.decodeStringOrEnumSchema(
                from: container,
                title: title,
                description: description
            )
        case "number", "integer":
            self = try Self.decodeNumberSchema(
                from: container,
                title: title,
                description: description
            )
        case "boolean":
            let defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .default)
            self = .boolean(title: title, description: description, defaultValue: defaultValue)
        case "array":
            self = try Self.decodeArraySchema(
                from: container,
                title: title,
                description: description
            )
        case "object":
            self = try Self.decodeObjectSchema(
                from: container,
                title: title,
                description: description
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unsupported schema type: \(type)"
            )
        }
    }

    /// Decodes `oneOf` / `anyOf` schema variants if present, returning `nil` otherwise.
    private static func decodeUnionSchema(
        from container: KeyedDecodingContainer<CodingKeys>,
        title: String?,
        description: String?
    ) throws -> JSONSchema? {
        if let oneOfSchemas = try container.decodeIfPresent([JSONSchema].self, forKey: .oneOf) {
            return .oneOf(oneOfSchemas, title: title, description: description)
        }
        if let anyOfSchemas = try container.decodeIfPresent([JSONSchema].self, forKey: .anyOf) {
            return .oneOf(anyOfSchemas, title: title, description: description)
        }
        return nil
    }

    /// Resolves the schema's declared `type`, falling back to structural inference and finally
    /// to `"string"` to keep tool discovery resilient to non-standard third-party schemas.
    private static func resolveSchemaType(
        from container: KeyedDecodingContainer<CodingKeys>
    ) -> String {
        if let singleType = try? container.decode(String.self, forKey: .type) {
            return singleType
        }
        if let typeArray = try? container.decode([String].self, forKey: .type),
           let resolvedType = typeArray.first(where: { $0 != "null" }) {
            // JSON Schema can express nullable types as e.g. ["string", "null"].
            return resolvedType
        }
        if (try? container.decodeIfPresent(JSONSchema.self, forKey: .items)) != nil {
            return "array"
        }
        if (try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .properties)) != nil {
            return "object"
        }
        if (try? container.decodeIfPresent([String].self, forKey: .enumValues)) != nil {
            return "string"
        }
        // Be permissive for non-standard schemas from third-party MCP servers.
        // Fallback to string to keep tool discovery/proxy generation functional.
        return "string"
    }

    /// Decodes a `"string"`-typed schema, returning either an enum or a plain string schema.
    private static func decodeStringOrEnumSchema(
        from container: KeyedDecodingContainer<CodingKeys>,
        title: String?,
        description: String?
    ) throws -> JSONSchema {
        let defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .default)
        if let enumValues = try container.decodeIfPresent([String].self, forKey: .enumValues) {
            let enumNames = try container.decodeIfPresent([String].self, forKey: .enumNames)
            return .enum(
                values: enumValues,
                title: title,
                description: description,
                enumNames: enumNames,
                defaultValue: defaultValue
            )
        }
        let format = try container.decodeIfPresent(String.self, forKey: .format)
        let minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
        let maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
        return .string(
            title: title,
            description: description,
            format: format,
            minLength: minLength,
            maxLength: maxLength,
            defaultValue: defaultValue
        )
    }

    /// Decodes a numeric (`"number"` or `"integer"`) schema.
    private static func decodeNumberSchema(
        from container: KeyedDecodingContainer<CodingKeys>,
        title: String?,
        description: String?
    ) throws -> JSONSchema {
        let minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        let maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        let defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .default)
        return .number(
            title: title,
            description: description,
            minimum: minimum,
            maximum: maximum,
            defaultValue: defaultValue
        )
    }

    /// Decodes an `"array"`-typed schema.
    private static func decodeArraySchema(
        from container: KeyedDecodingContainer<CodingKeys>,
        title: String?,
        description: String?
    ) throws -> JSONSchema {
        let items = try container.decode(JSONSchema.self, forKey: .items)
        let defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .default)
        return .array(items: items, title: title, description: description, defaultValue: defaultValue)
    }

    /// Decodes an `"object"`-typed schema, including its properties and `additionalProperties` form.
    private static func decodeObjectSchema(
        from container: KeyedDecodingContainer<CodingKeys>,
        title: String?,
        description: String?
    ) throws -> JSONSchema {
        var properties: [String: JSONSchema] = [:]
        if let propertiesContainer = try? container.nestedContainer(
            keyedBy: AnyCodingKey.self,
            forKey: .properties
        ) {
            for key in propertiesContainer.allKeys {
                properties[key.stringValue] = try propertiesContainer.decode(JSONSchema.self, forKey: key)
            }
        }
        let required = try container.decodeIfPresent([String].self, forKey: .required) ?? []

        let additionalProperties = try decodeAdditionalProperties(from: container)
        let defaultValue = try container.decodeIfPresent(JSONValue.self, forKey: .default)

        return .object(
            JSONSchema.Object(
                properties: properties,
                required: required,
                title: title,
                description: description,
                additionalProperties: additionalProperties
            ),
            defaultValue: defaultValue
        )
    }

    /// Decodes the `additionalProperties` field, accepting either a Boolean or a nested schema.
    private static func decodeAdditionalProperties(
        from container: KeyedDecodingContainer<CodingKeys>
    ) throws -> Bool? {
        if let boolValue = try? container.decodeIfPresent(Bool.self, forKey: .additionalProperties) {
            return boolValue
        }
        if (try? container.decodeIfPresent(JSONSchema.self, forKey: .additionalProperties)) != nil {
            // JSON Schema allows `additionalProperties` to be either a Boolean or another schema.
            // SwiftMCP's in-memory model currently stores only the Boolean form, so preserve
            // permissive behavior when a schema object is provided by third-party MCP servers.
            return true
        }
        return nil
    }

}
