//
//  JSONSchema+Codable.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 19.04.25.
//

import Foundation

/**
 Extension to make JSONSchema conform to Codable
 */
extension JSONSchema: Codable {
    /// Coding keys for JSONSchema encoding and decoding
    private enum CodingKeys: String, CodingKey {
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
    }

/**
	 Creates a new JSONSchema instance by decoding from the given decoder.
	 
	 - Parameter decoder: The decoder to read data from
	 - Throws: DecodingError if the data is corrupted or if an unsupported schema type is encountered
	 */
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let description = try container.decodeIfPresent(String.self, forKey: .description)

        switch type {
            case "string":

                if let enumValues = try container.decodeIfPresent([String].self, forKey: .enumValues)
				{
                    let enumNames = try container.decodeIfPresent([String].self, forKey: .enumNames)
                    self = .enum(values: enumValues, title: title, description: description, enumNames: enumNames)
                }
				else
				{
                    let format = try container.decodeIfPresent(String.self, forKey: .format)
                    let minLength = try container.decodeIfPresent(Int.self, forKey: .minLength)
                    let maxLength = try container.decodeIfPresent(Int.self, forKey: .maxLength)
                    self = .string(title: title, description: description, format: format, minLength: minLength, maxLength: maxLength)
                }

            case "number", "integer":
                let minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
                let maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
                self = .number(title: title, description: description, minimum: minimum, maximum: maximum)
            case "boolean":
                let defaultValue = try container.decodeIfPresent(Bool.self, forKey: .default)
                self = .boolean(title: title, description: description, default: defaultValue)
            case "array":
                let items = try container.decode(JSONSchema.self, forKey: .items)
                self = .array(items: items, title: title, description: description)
            case "object":
                var properties: [String: JSONSchema] = [:]
                if let propertiesContainer = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .properties) {
                    for key in propertiesContainer.allKeys {
                        properties[key.stringValue] = try propertiesContainer.decode(JSONSchema.self, forKey: key)
                    }
                }
                let required = try container.decodeIfPresent([String].self, forKey: .required) ?? []

                let additionalPropertes = try container.decodeIfPresent(Bool.self, forKey: .additionalProperties)

                self = .object(JSONSchema.Object(properties: properties, required: required, title: title, description: description, additionalProperties: additionalPropertes))
            default:
                throw DecodingError.dataCorruptedError(
					forKey: .type,
					in: container,
					debugDescription: "Unsupported schema type: \(type)"
				)
        }
    }

/**
	 Encodes this JSONSchema instance into the given encoder.
	 
	 - Parameter encoder: The encoder to write data to
	 - Throws: EncodingError if the data cannot be encoded
	 */
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
            case .string(let title, let description, let format, let minLength, let maxLength):
                try container.encode("string", forKey: .type)
                try container.encodeIfPresent(title, forKey: .title)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encodeIfPresent(format, forKey: .format)
                try container.encodeIfPresent(minLength, forKey: .minLength)
                try container.encodeIfPresent(maxLength, forKey: .maxLength)
            case .number(let title, let description, let minimum, let maximum):
                try container.encode("number", forKey: .type)
                try container.encodeIfPresent(title, forKey: .title)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encodeIfPresent(minimum, forKey: .minimum)
                try container.encodeIfPresent(maximum, forKey: .maximum)
            case .boolean(let title, let description, let defaultValue):
                try container.encode("boolean", forKey: .type)
                try container.encodeIfPresent(title, forKey: .title)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encodeIfPresent(defaultValue, forKey: .default)
            case .array(let items, let title, let description):
                try container.encode("array", forKey: .type)
                try container.encode(items, forKey: .items)
                try container.encodeIfPresent(title, forKey: .title)
                try container.encodeIfPresent(description, forKey: .description)
            case .object(let object):
                try container.encode("object", forKey: .type)

                var propertiesContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .properties)
                for (key, value) in object.properties {
                    try propertiesContainer.encode(value, forKey: AnyCodingKey(stringValue: key)!)
                }

                if !object.required.isEmpty {
                    try container.encode(object.required, forKey: .required)
                }

                try container.encodeIfPresent(object.title, forKey: .title)
                try container.encodeIfPresent(object.description, forKey: .description)

                try container.encodeIfPresent(object.additionalProperties, forKey: .additionalProperties)

            case .enum(let values, let title, let description, let enumNames):
                try container.encode("string", forKey: .type)
                try container.encodeIfPresent(title, forKey: .title)
                try container.encodeIfPresent(description, forKey: .description)
                try container.encode(values, forKey: .enumValues)
                try container.encodeIfPresent(enumNames, forKey: .enumNames)
        }
    }
}

/**
 A coding key that can be initialized with any string value.
 Used for encoding and decoding dynamic property names in JSON schemas.
 */
private struct AnyCodingKey: CodingKey {
    /// The string value of the coding key
    var stringValue: String
    /// The integer value of the coding key, if any
    var intValue: Int?

/**
	 Creates a coding key from a string value.
	 
	 - Parameter stringValue: The string value for the key
	 - Returns: A coding key, or nil if the string value is invalid
	 */
    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

/**
	 Creates a coding key from an integer value.
	 
	 - Parameter intValue: The integer value for the key
	 - Returns: A coding key, or nil if the integer value is invalid
	 */
    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}
