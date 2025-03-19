import Foundation
import ArgumentParser
import SwiftMCP
import Logging
import NIOCore
#if canImport(OSLog)
import OSLog
#endif

/**
 A command that processes JSON-RPC requests from standard input and writes responses to standard output.
 
 This is the default mode of operation for the SwiftMCP demo. It's designed to:
 - Read JSON-RPC requests line by line from stdin
 - Process each request using the configured MCP server
 - Write JSON-RPC responses to stdout
 - Log status messages to stderr to avoid interfering with the JSON-RPC protocol
 
 This mode is particularly useful for:
 - Integration with other tools via Unix pipes
 - Testing and debugging MCP functions
 - Scripting and automation
 */
struct StdioCommand: AsyncParsableCommand {
    static var configuration = CommandConfiguration(
        commandName: "stdio",
        abstract: "Read JSON-RPC requests from stdin and write responses to stdout",
        discussion: """
  Read JSON-RPC requests from stdin and write responses to stdout.
  
  This mode is perfect for integration with other tools via pipes.
  
  Examples:
    # Basic usage
    SwiftMCPDemo stdio
    
    # With pipe
    echo '{"jsonrpc": "2.0", "method": "add", "params": [1, 2]}' | SwiftMCPDemo stdio
"""
    )
    
	func run() async throws {
#if canImport(OSLog)
        LoggingSystem.bootstrapWithOSLog()
#endif
        
        let calculator = Calculator()
        
        do {
            // need to output to stderror or else npx complains
            fputs("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with Stdio transport\n", stderr)
            
            let transport = StdioTransport(server: calculator)
			try await transport.run()
        }
        catch let error as IOError {
            // Handle specific IO errors with more detail
            let errorMessage = """
                IO Error: \(error)
                Code: \(error.errnoCode)
                """
            fputs("\(errorMessage)\n", stderr)
            Foundation.exit(1)
        }
        catch let error as ChannelError {
            // Handle specific channel errors
            fputs("Channel Error: \(error)\n", stderr)
            Foundation.exit(1)
        }
        catch {
            // Handle any other errors
            fputs("Error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }
} 
