import Foundation

/// Configuration options for connecting to an MCP server.
public enum MCPServerConfig: Sendable {
    /// Connect to an MCP server via standard input/output (stdio).
    case stdio(config: MCPServerStdioConfig)
    
    /// Connect to an MCP server via in-process stdio handles.
    case stdioHandles(server: any MCPServer & Sendable)

    /// Connect to an MCP server via TCP with optional Bonjour discovery.
    case tcp(config: MCPServerTcpConfig)

    /// Connect to an MCP server via Server-Sent Events (SSE).
    case sse(config: MCPServerSseConfig)
}
