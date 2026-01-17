import ArgumentParser

/**
 Command-line interface for the SwiftMCP AppIntents demo.
 
 This demo exposes AppIntents as MCP tools using multiple transport options:
 
 - `stdio`: Read JSON-RPC from stdin and write responses to stdout.
 - `httpsse`: Run an HTTP server with SSE + JSON-RPC endpoints.
 - `tcp`: Run a TCP server with Bonjour discovery.
 */
@main
struct MCPCommand: AsyncParsableCommand {
#if canImport(Network)
    static let configuration = CommandConfiguration(
        commandName: "SwiftMCPIntentsDemo",
        abstract: "Expose AppIntents as MCP tools over multiple transports",
        discussion: """
  Expose AppIntents as MCP tools.
  
  The command can operate in three modes:
  
  1. stdio:
     - Reads JSON-RPC requests from stdin
     - Writes responses to stdout
     - Example: SwiftMCPIntentsDemo stdio
  
  2. httpsse:
     - Starts an HTTP server with Server-Sent Events (SSE) support
     - Supports bearer token authentication and OpenAPI endpoints
     - Example: SwiftMCPIntentsDemo httpsse --port 8080 --openapi
  
  3. tcp:
     - Starts a TCP server with Bonjour discovery (_mcp._tcp)
     - Example: SwiftMCPIntentsDemo tcp --name "SwiftMCP Intents Demo"
""",
        subcommands: [StdioCommand.self, HTTPSSECommand.self, TCPBonjourCommand.self],
        defaultSubcommand: StdioCommand.self
    )
#else
    static let configuration = CommandConfiguration(
        commandName: "SwiftMCPIntentsDemo",
        abstract: "Expose AppIntents as MCP tools over multiple transports",
        discussion: """
  Expose AppIntents as MCP tools.
  
  The command can operate in two modes:
  
  1. stdio:
     - Reads JSON-RPC requests from stdin
     - Writes responses to stdout
     - Example: SwiftMCPIntentsDemo stdio
  
  2. httpsse:
     - Starts an HTTP server with Server-Sent Events (SSE) support
     - Supports bearer token authentication and OpenAPI endpoints
     - Example: SwiftMCPIntentsDemo httpsse --port 8080 --openapi
""",
        subcommands: [StdioCommand.self, HTTPSSECommand.self],
        defaultSubcommand: StdioCommand.self
    )
#endif
}

