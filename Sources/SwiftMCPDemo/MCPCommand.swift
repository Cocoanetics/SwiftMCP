import Foundation
import ArgumentParser
import SwiftMCP
import Logging
import AnyCodable
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

#if canImport(OSLog)
import OSLog
#endif

/// Command-line interface for the SwiftMCP demo
@main
struct MCPCommand: ParsableCommand {

	static var configuration = CommandConfiguration(
		commandName: "mcp",
		abstract: "A utility for testing SwiftMCP functions",
		discussion: """
  Process JSON-RPC requests for SwiftMCP functions.
  
  By default, the command reads JSON-RPC requests from stdin and writes responses to stdout.
  If a port is specified, it starts an HTTP server with SSE support.
  """
	)
	
	@Option(name: .long, help: "The port to listen on for HTTP requests. If not specified, uses stdin/stdout.")
	var port: Int?
	
	/// The main entry point for the command
	func run() throws {
		
		#if canImport(OSLog)
			LoggingSystem.bootstrapWithOSLog()
		#endif
		
		// Create an instance of the Calculator
		let calculator = Calculator()
		
		do {
			if let port = port {
				// Start HTTP+SSE transport
				try HTTPSSETransport(server: calculator, port: port).start()
			} else {
				// Use standard input/output
				try StdioTransport(server: calculator).start()
			}
		}
		catch
		{
			fputs("Error: \(error.localizedDescription)\n", stderr)
			Foundation.exit(1)
		}
	}
}
