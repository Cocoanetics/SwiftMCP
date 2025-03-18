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
  
  1. stdio (default):
     - Reads JSON-RPC requests from stdin
     - Writes responses to stdout
     - Perfect for integration with other tools via pipes
     - Example: echo '{"jsonrpc": "2.0", "method": "add", "params": [1, 2]}' | SwiftMCPDemo
  
  2. HTTP+SSE:
     - Starts an HTTP server with Server-Sent Events (SSE) support
     - Requires --port to be specified
     - Supports optional bearer token authentication
     - Can expose OpenAPI endpoints for AI plugin integration
     - Example: SwiftMCPDemo --transport httpsse --port 8080
  
  When using HTTP+SSE mode:
  - Use --token to require bearer token authentication
  - Use --openapi to expose AI plugin manifest and OpenAPI spec
  - Connect to http://localhost:<port>/sse for SSE
  - Send JSON-RPC requests to http://localhost:<port>/<serverName>/<toolName>
"""
	)
	
	@Option(name: .long, help: "The transport type to use (stdio or httpsse)")
	var transport: TransportType = .stdio
	
	@Option(name: .long, help: "The port to listen on (required when transport is HTTP+SSE)")
	var port: Int?
    
    @Option(name: .long, help: "Bearer token for authorization (optional, HTTP+SSE only)")
    var token: String?
    
    @Flag(name: .long, help: "Enable OpenAPI endpoints (optional, HTTP+SSE only)")
    var openapi: Bool = false
	
	func validate() throws {
		switch transport {
			case .stdio:
				// For stdio transport, ensure HTTP+SSE specific options are not set
				if port != nil {
					throw ValidationError("Port cannot be specified when using stdio transport")
				}
				if token != nil {
					throw ValidationError("Token cannot be specified when using stdio transport")
				}
				if openapi {
					throw ValidationError("OpenAPI cannot be enabled when using stdio transport")
				}
				
			case .httpsse:
				// For HTTP+SSE transport, port is required
				if port == nil {
					throw ValidationError("Port must be specified when using HTTP+SSE transport")
				}
		}
	}
	
	/// The main entry point for the command
	mutating func run() throws {
		
#if canImport(OSLog)
		LoggingSystem.bootstrapWithOSLog()
#endif
		
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
                    
                    // Set up authorization handler if token is provided
                    if let requiredToken = token {
                        transport.authorizationHandler = { token in
							
							guard let token else {
								return .unauthorized("Missing bearer token")
							}
							
                            guard token == requiredToken else {
								return .unauthorized("Invalid bearer token")
                            }
							
							return .authorized
                        }
                    }
                    
                    // Enable OpenAPI endpoints if requested
                    transport.serveOpenAPI = openapi
					
					// Set up signal handling to shut down the transport on Ctrl+C
					setupSignalHandler(transport: transport)
					
					// Run the server (blocking)
					try transport.run()
			}

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
