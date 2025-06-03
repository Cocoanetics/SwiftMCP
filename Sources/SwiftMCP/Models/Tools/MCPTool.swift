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
