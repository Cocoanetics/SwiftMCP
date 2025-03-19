//
//  MCPTool.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/// Represents a tool that can be used by an AI model
public struct MCPTool: Sendable {
	/// The name of the tool
	public let name: String
	
	/// An optional description of the tool
	public let description: String?
	
	/// The JSON schema defining the tool's input parameters
	public let inputSchema: JSONSchema
	
	/**
	 Creates a new tool with the specified name, description, and input schema.
	 
	 - Parameters:
	   - name: The name of the tool
	   - description: An optional description of the tool
	   - inputSchema: The schema defining the function's input parameters
	 */
	public init(name: String, description: String? = nil, inputSchema: JSONSchema) {
		self.name = name
		self.description = description
		self.inputSchema = inputSchema
	}
} 

/**
 Extension to make MCPTool conform to Codable
 */
extension MCPTool: Codable {
	// MARK: - Codable Implementation
	
	private enum CodingKeys: String, CodingKey {
		case name
		case description
		case inputSchema
	}
	
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let name = try container.decode(String.self, forKey: .name)
		let description = try container.decodeIfPresent(String.self, forKey: .description)
		let inputSchema = try container.decode(JSONSchema.self, forKey: .inputSchema)
		
		self.init(name: name, description: description, inputSchema: inputSchema)
	}
	
	public func encode(to encoder: Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(name, forKey: .name)
		try container.encodeIfPresent(description, forKey: .description)
		try container.encode(inputSchema, forKey: .inputSchema)
	}
}

/**
 Extension to provide utility methods for working with MCP tools.
 */
extension MCPTool {
	/**
	 Enriches a dictionary of arguments with default values for any missing parameters.
	 
	 - Parameters:
	   - arguments: The original arguments dictionary
	   - object: The object containing the function metadata
	 
	 - Returns: A new dictionary with default values added for missing parameters
	 - Throws: MCPToolError if required parameters are missing or if parameter conversion fails
	 */
	public func enrichArguments(_ arguments: [String: Any], forObject object: Any) throws -> [String: Any] {
		// Use the provided function name or fall back to the tool's name
		let metadataKey = "__mcpMetadata_\(name)"
		
		// Create a copy of the arguments dictionary
		var enrichedArguments = arguments
		
		// Find the metadata for the function using reflection
		let mirror = Mirror(reflecting: object)
		guard let child = mirror.children.first(where: { $0.label == metadataKey }),
			  let metadata = child.value as? MCPToolMetadata else {
			// If no metadata is found, return the original arguments
			return arguments
		}
		
		// Check for missing required parameters
		for param in metadata.parameters {
			if enrichedArguments[param.name] == nil && param.defaultValue == nil {
				throw MCPToolError.missingRequiredParameter(parameterName: param.name)
			}
		}
		
		// Add default values for parameters that are missing from the arguments dictionary
		for param in metadata.parameters {
			if enrichedArguments[param.name] == nil, let defaultValue = param.defaultValue {
				// Convert the default value to the appropriate type based on the parameter type
				switch param.type {
				case "Int":
					if let intValue = Int(defaultValue) {
						enrichedArguments[param.name] = intValue
					}
				case "Double", "Float":
					if let doubleValue = Double(defaultValue) {
						enrichedArguments[param.name] = doubleValue
					}
				case "Bool":
					if let boolValue = Bool(defaultValue) {
						enrichedArguments[param.name] = boolValue
					}
				default:
					// For string and other types, use the default value as is
					enrichedArguments[param.name] = defaultValue
				}
			}
		}
		
		return enrichedArguments
	}
}

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
		/// A description of the schema
		case description
		/// The schema for array items
		case items
	}
	
	/**
	 Creates a new JSONSchema instance by decoding from the given decoder.
	 
	 - Parameter decoder: The decoder to read data from
	 - Throws: DecodingError if the data is corrupted or if an unsupported schema type is encountered
	 */
	public init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)
		let type = try container.decode(String.self, forKey: .type)
		let description = try container.decodeIfPresent(String.self, forKey: .description)
		
		switch type {
		case "string":
			self = .string(description: description)
		case "number":
			self = .number(description: description)
		case "boolean":
			self = .boolean(description: description)
		case "array":
			let items = try container.decode(JSONSchema.self, forKey: .items)
			self = .array(items: items, description: description)
		case "object":
			var properties: [String: JSONSchema] = [:]
			if let propertiesContainer = try? container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .properties) {
				for key in propertiesContainer.allKeys {
					properties[key.stringValue] = try propertiesContainer.decode(JSONSchema.self, forKey: key)
				}
			}
			let required = try container.decodeIfPresent([String].self, forKey: .required) ?? []
			self = .object(properties: properties, required: required, description: description)
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
		case .string(let description):
			try container.encode("string", forKey: .type)
			try container.encodeIfPresent(description, forKey: .description)
		case .number(let description):
			try container.encode("number", forKey: .type)
			try container.encodeIfPresent(description, forKey: .description)
		case .boolean(let description):
			try container.encode("boolean", forKey: .type)
			try container.encodeIfPresent(description, forKey: .description)
		case .array(let items, let description):
			try container.encode("array", forKey: .type)
			try container.encode(items, forKey: .items)
			try container.encodeIfPresent(description, forKey: .description)
		case .object(let properties, let required, let description):
			try container.encode("object", forKey: .type)
			
			var propertiesContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .properties)
			for (key, value) in properties {
				try propertiesContainer.encode(value, forKey: AnyCodingKey(stringValue: key)!)
			}
			
			if !required.isEmpty {
				try container.encode(required, forKey: .required)
			}
			
			try container.encodeIfPresent(description, forKey: .description)
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
