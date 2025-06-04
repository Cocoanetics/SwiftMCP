import Foundation
import AnyCodable

/// Represents a prompt that can be provided by an MCP server
public struct Prompt: Encodable, Sendable {
    /// Unique name of the prompt
    public let name: String

    /// Optional description of the prompt
    public let description: String?

    /// Arguments that the prompt accepts
    public let arguments: [MCPParameterInfo]

    public init(name: String, description: String? = nil, arguments: [MCPParameterInfo] = []) {
        self.name = name
        self.description = description
        self.arguments = arguments
    }
}

extension Prompt {
    private enum CodingKeys: String, CodingKey {
        case name, description, arguments
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        let args: [[String: AnyCodable]] = arguments.map { param in
            [
                "name": AnyCodable(param.name),
                "description": AnyCodable(param.description as Any?),
                "required": AnyCodable(param.isRequired)
            ]
        }
        try container.encode(args, forKey: .arguments)
    }
}
