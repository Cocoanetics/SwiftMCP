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
	
	enum TransportType: String, ExpressibleByArgument {
		case stdio
		case httpsse
	}
	
	static var configuration = CommandConfiguration(
		commandName: "SwiftMCPDemo",
		abstract: "A utility for testing SwiftMCP functions",
		discussion: """
  Process JSON-RPC requests for SwiftMCP functions.
  
  The command can operate in two modes:
  
  - stdio: Reads JSON-RPC requests from stdin and writes responses to stdout
  - httpsse: Starts an HTTP server with Server-Sent Events (SSE) support on the specified port
"""
	)
	
	@Option(name: .long, help: "The transport type to use (stdio or httpsse)")
	var transport: TransportType = .stdio
	
	@Option(name: .long, help: "The port to listen on (required when transport is HTTP+SSE)")
	var port: Int?
	
	func validate() throws {
		if transport == .httpsse && port == nil {
			throw ValidationError("Port must be specified when using HTTP+SSE transport")
		}
	}
	
	/// The main entry point for the command
	mutating func run() throws {
		
#if canImport(OSLog)
		LoggingSystem.bootstrapWithOSLog()
#endif
		
		// Check if transport type is specified
		if CommandLine.arguments.contains("--transport") == false {
			print(MCPCommand.helpMessage())
			Foundation.exit(0)
		}
		
		// Set up signal handler for graceful shutdown
		signal(SIGINT) { _ in
			print("\nShutting down...")
			Foundation.exit(0)
		}

		let calculator = Calculator()
		
		switch transport {
				
			case .stdio:
				
				print("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with Stdio transport")

				let transport = StdioTransport(server: calculator)
				try transport.start()
				
			case .httpsse:
				
				guard let port else {
					fatalError("Port should have been validated")
				}
				
				let host = String.localHostname
				print("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with HTTP+SSE transport on http://\(host):\(port)/sse")

				let transport = HTTPSSETransport(server: calculator, port: port)

				try transport.start()
		}
	}
}
