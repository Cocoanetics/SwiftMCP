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

    /// The JSON schema defining the tool's output, if available
    public let outputSchema: JSONSchema?

    /// Optional annotations providing hints about tool behavior (per MCP spec)
    public let annotations: MCPToolAnnotations?

/**
	 Creates a new tool with the specified name, description, and input schema.

	 - Parameters:
	   - name: The name of the tool
	   - description: An optional description of the tool
	   - inputSchema: The schema defining the function's input parameters
       - outputSchema: The schema defining the function's output, if available
       - annotations: Optional hints about tool behavior
	 */
    public init(
        name: String,
        description: String? = nil,
        inputSchema: JSONSchema,
        outputSchema: JSONSchema? = nil,
        annotations: MCPToolAnnotations? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
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
        case outputSchema
        case annotations
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let name = try container.decode(String.self, forKey: .name)
        let description = try container.decodeIfPresent(String.self, forKey: .description)
        let inputSchema = try container.decode(JSONSchema.self, forKey: .inputSchema)
        let outputSchema = try container.decodeIfPresent(JSONSchema.self, forKey: .outputSchema)
        let annotations = try container.decodeIfPresent(MCPToolAnnotations.self, forKey: .annotations)

        self.init(name: name, description: description, inputSchema: inputSchema, outputSchema: outputSchema, annotations: annotations)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encode(inputSchema, forKey: .inputSchema)
        try container.encodeIfPresent(outputSchema, forKey: .outputSchema)
        try container.encodeIfPresent(annotations, forKey: .annotations)
    }
}
