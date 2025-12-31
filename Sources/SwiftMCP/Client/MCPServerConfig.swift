import Foundation

/// Configuration options for connecting to an MCP server.
public enum MCPServerConfig: Codable, Equatable, Sendable {
    /// Connect to an MCP server via standard input/output (stdio).
    case stdio(config: MCPServerStdioConfig)

    /// Connect to an MCP server via Server-Sent Events (SSE).
    case sse(config: MCPServerSseConfig)

    private enum CodingKeys: String, CodingKey {
        case type
        case config
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "stdio":
            let config = try container.decode(MCPServerStdioConfig.self, forKey: .config)
            self = .stdio(config: config)
        case "sse":
            let config = try container.decode(MCPServerSseConfig.self, forKey: .config)
            self = .sse(config: config)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Invalid type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .stdio(let config):
            try container.encode("stdio", forKey: .type)
            try container.encode(config, forKey: .config)
        case .sse(let config):
            try container.encode("sse", forKey: .type)
            try container.encode(config, forKey: .config)
        }
    }
}
