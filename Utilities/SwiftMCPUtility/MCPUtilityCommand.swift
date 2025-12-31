import ArgumentParser
import Foundation

/// Command-line utility for interacting with MCP servers.
@main
struct MCPUtilityCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "SwiftMCPUtility",
        abstract: "Utilities for connecting to MCP servers",
        discussion: """
  Connect to MCP servers over stdio or HTTP+SSE to inspect tools and capabilities.

  Examples:
    SwiftMCPUtility tools --sse http://localhost:8080/sse
    SwiftMCPUtility tools --command "npx -y @modelcontextprotocol/server-filesystem"
    SwiftMCPUtility tools --config mcp.json
    SwiftMCPUtility capabilities --sse http://localhost:8080/sse -o caps.txt

  Config JSON format:
    {
      "sse": "http://localhost:8080/sse",
      "headers": { "Authorization": "Bearer token" }
    }

    {
      "command": "npx -y @modelcontextprotocol/server-filesystem",
      "cwd": "/tmp",
      "env": { "NODE_ENV": "development" }
    }
""",
        subcommands: [ToolsCommand.self, CapabilitiesCommand.self]
    )
}
