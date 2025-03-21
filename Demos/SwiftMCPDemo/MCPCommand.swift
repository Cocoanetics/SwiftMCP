import Foundation
import ArgumentParser
import SwiftMCP
import Logging
import NIOCore
import Dispatch

#if canImport(OSLog)
import OSLog
#endif

/**
 Command-line interface for the SwiftMCP demo.
 
 This is the main entry point for the SwiftMCP demo application. It provides two modes of operation:
 
 - `stdio`: The default mode that processes JSON-RPC requests from standard input and writes responses to standard output.
   Perfect for integration with other tools via pipes.
 
 - `httpsse`: Starts an HTTP server with Server-Sent Events (SSE) support, optionally with authentication and OpenAPI endpoints.
   Ideal for long-running services and AI plugin integration.
 
 Example usage:
 ```bash
 # Using stdio mode (default)
 echo '{"jsonrpc": "2.0", "method": "add", "params": [1, 2]}' | SwiftMCPDemo
 
 # Using HTTP+SSE mode
 SwiftMCPDemo httpsse --port 8080 --token secret --openapi
 ```
 */
@main
struct MCPCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "SwiftMCPDemo",
        abstract: "A utility for testing SwiftMCP functions",
        discussion: """
  Process JSON-RPC requests for SwiftMCP functions.
  
  The command can operate in two modes:
  
  1. stdio:
     - Reads JSON-RPC requests from stdin
     - Writes responses to stdout
     - Perfect for integration with other tools via pipes
     - Example: echo '{"jsonrpc": "2.0", "method": "add", "params": [1, 2]}' | SwiftMCPDemo stdio
  
  2. httpsse:
     - Starts an HTTP server with Server-Sent Events (SSE) support
     - Supports bearer token authentication and OpenAPI endpoints
     - Example: SwiftMCPDemo httpsse --port 8080
""",
        subcommands: [StdioCommand.self, HTTPSSECommand.self],
        defaultSubcommand: StdioCommand.self
    )
} 
