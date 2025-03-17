import Foundation
import ArgumentParser
import SwiftMCP
import Logging
import AnyCodable
import NIOCore
import Dispatch
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
		
		let calculator = Calculator()
		
		do {
			switch transport {
					
				case .stdio:
					
					// need to output to stderror or else npx complains
					fputs("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with Stdio transport\n", stderr)
					
					let transport = StdioTransport(server: calculator)
					try transport.run()
					
				case .httpsse:
					
					guard let port else {
						fatalError("Port should have been validated")
					}
					
					let host = String.localHostname
					print("MCP Server \(calculator.serverName) (\(calculator.serverVersion)) started with HTTP+SSE transport on http://\(host):\(port)/sse")
					
					let transport = HTTPSSETransport(server: calculator, port: port)
					
					// Set up signal handling to shut down the transport on Ctrl+C
					setupSignalHandler(transport: transport)
					
					try transport.run()
			}
		}
		catch let error as IOError {
			let humanReadable = String(cString: strerror(error.errnoCode))
			
			fputs("IO Error: \(humanReadable)\n", stderr)
			Foundation.exit(1)
		}
		catch {
			// Handle any other errors
			fputs("Error: \(error.localizedDescription)\n", stderr)
			Foundation.exit(1)
		}
	}
}
