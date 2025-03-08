//
//  MCPTool.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/**
 MCPTool represents a tool for Model Context Protocol (MCP).

 This struct is primarily designed for encoding and decoding JSON representations
 of functions, making them accessible to AI models and other systems that need to
 understand the function's signature, parameters, and behavior.

 Each MCPTool contains:
 - A name identifying the function
 - An optional description explaining the function's purpose
 - An inputSchema defining the parameters the function accepts

 The JSON encoding implementation handles special cases for numeric and boolean values,
 ensuring they are properly represented without quotes in the JSON output.
 */
public struct MCPTool: Codable {
	// MARK: - Properties
	
	/// The name of the function
	public let name: String
	
	/// An optional description of the function's purpose
	public let description: String?
	
	/// The schema defining the function's input parameters
	public let inputSchema: JSONSchema
	
	// MARK: - Initialization
	
	/**
	 Creates a new MCPTool instance.

	 - Parameters:
	   - name: The name of the function
	   - description: An optional description of the function's purpose
	   - inputSchema: The schema defining the function's input parameters
	 */
	public init(name: String, description: String? = nil, inputSchema: JSONSchema) {
		self.name = name
		self.description = description
		self.inputSchema = inputSchema
	}
	
	// MARK: - Codable Implementation
	
	private enum CodingKeys: String, CodingKey {
		case name
		case description
		case inputSchema
	}
	
	/**
	 Represents the JSON schema for a function's input parameters.

	 This struct defines the structure of a function's parameters, including:
	 - The type of the schema (typically "object")
	 - The properties representing individual parameters
	 - The required parameters that must be provided
	 */
	public struct JSONSchema: Codable {
		// MARK: - Properties
		
		/// The type of the schema (typically "object")
		public let type: String
		
		/// The properties representing individual parameters
		public let properties: [String: Property]?
		
		/// The required parameters that must be provided
		public let required: [String]?
		
		// MARK: - Initialization
		
		/**
		 Creates a new JSONSchema instance.

		 - Parameters:
		   - type: The type of the schema (typically "object")
		   - properties: The properties representing individual parameters
		   - required: The required parameters that must be provided
		 */
		public init(type: String, properties: [String: Property]? = nil, required: [String]? = nil) {
			self.type = type
			self.properties = properties
			self.required = required
		}
		
		// MARK: - Codable Implementation
		
		private enum CodingKeys: String, CodingKey {
			case type
			case properties
			case required
		}
		
		/**
		 Represents a property in a JSON schema.

		 This class defines the structure of a parameter, including:
		 - The type of the parameter (e.g., "string", "number", "boolean")
		 - An optional description of the parameter
		 - Optional nested items for array types
		 - An optional default value
		 */
		public class Property: Codable {
			// MARK: - Properties
			
			/// The type of the parameter (e.g., "string", "number", "boolean")
			public let type: String
			
			/// An optional description of the parameter
			public let description: String?
			
			/// Optional nested items for array types
			public let items: Property?
			
			/// An optional default value
			public let defaultValue: String?
			
			// MARK: - Initialization
			
			/**
			 Creates a new Property instance.

			 - Parameters:
			   - type: The type of the parameter
			   - description: An optional description of the parameter
			   - items: Optional nested items for array types
			   - defaultValue: An optional default value
			 */
			public init(type: String, description: String? = nil, items: Property? = nil, defaultValue: String? = nil) {
				self.type = type
				self.description = description
				self.items = items
				self.defaultValue = defaultValue
			}
			
			// MARK: - Codable Implementation
			
			enum CodingKeys: String, CodingKey {
				case type
				case description
				case items
				case defaultValue = "default"
			}
			
			// MARK: - Decodable Implementation
			
			public required init(from decoder: Decoder) throws {
				let container = try decoder.container(keyedBy: CodingKeys.self)
				
				// Decode the basic properties
				type = try container.decode(String.self, forKey: .type)
				description = try container.decodeIfPresent(String.self, forKey: .description)
				items = try container.decodeIfPresent(MCPTool.JSONSchema.Property.self, forKey: .items)
				
				// Handle default value based on type
				if container.contains(.defaultValue) {
					if type == "number" || type == "integer" {
						// For numeric types, try to decode as a number first
						if let numericValue = try? container.decode(Double.self, forKey: .defaultValue) {
							// Convert to string without decimal for integers
							if type == "integer" && numericValue.truncatingRemainder(dividingBy: 1) == 0 {
								defaultValue = String(Int(numericValue))
							} else {
								defaultValue = String(numericValue)
							}
						} else {
							// Fall back to string if it's not a valid number
							defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
						}
					} else if type == "boolean" {
						// For boolean types, try to decode as a boolean first
						if let boolValue = try? container.decode(Bool.self, forKey: .defaultValue) {
							defaultValue = boolValue ? "true" : "false"
						} else {
							// Fall back to string if it's not a valid boolean
							defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
						}
					} else {
						// For other types (string, array, etc.), decode as string
						defaultValue = try container.decodeIfPresent(String.self, forKey: .defaultValue)
					}
				} else {
					defaultValue = nil
				}
			}
			
			// MARK: - Encodable Implementation
			
			public func encode(to encoder: Encoder) throws {
				var container = encoder.container(keyedBy: CodingKeys.self)
				
				// Encode the basic properties
				try container.encode(type, forKey: .type)
				try container.encodeIfPresent(description, forKey: .description)
				try container.encodeIfPresent(items, forKey: .items)
				
				// Handle default value based on type
				if let defaultValue = defaultValue {
					if type == "number" || type == "integer" {
						// For numeric types, convert to Double or Int and encode directly
						if let doubleValue = Double(defaultValue) {
							if type == "integer" && doubleValue.truncatingRemainder(dividingBy: 1) == 0 {
								try container.encode(Int(doubleValue), forKey: .defaultValue)
							} else {
								try container.encode(doubleValue, forKey: .defaultValue)
							}
						} else {
							// Fall back to string if conversion fails
							try container.encode(defaultValue, forKey: .defaultValue)
						}
					} else if type == "boolean" {
						// For boolean types, convert to Bool and encode directly
						if defaultValue == "true" {
							try container.encode(true, forKey: .defaultValue)
						} else if defaultValue == "false" {
							try container.encode(false, forKey: .defaultValue)
						} else {
							// Fall back to string if conversion fails
							try container.encode(defaultValue, forKey: .defaultValue)
						}
					} else {
						// For other types (string, array, etc.), encode as string
						try container.encode(defaultValue, forKey: .defaultValue)
					}
				}
			}
		}
	}
}
