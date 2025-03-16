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
		// Set default log level to info - will only show important logs
		// Per the cursor rules: Use OS_LOG_DISABLE=1 to see log output as needed
		LoggingSystem.bootstrap { label in
			// Create an OSLog-based logger
			let category = label.split(separator: ".").last?.description ?? "default"
			let osLogger = OSLog(subsystem: "com.cocoanetics.SwiftMCP", category: category)
			
			// Set log level to info by default (or trace if SWIFT_LOG_LEVEL is set to trace)
			var handler = OSLogHandler(label: label, log: osLogger)
			
			// Check if we need verbose logging
			if ProcessInfo.processInfo.environment["ENABLE_DEBUG_OUTPUT"] == "1" {
				handler.logLevel = .trace
			} else {
				handler.logLevel = .info
			}
			
			return handler
		}
#endif
		
		// Create an instance of the Calculator
		let calculator = Calculator()
		
		if let port = port {
			// Start HTTP+SSE transport
			runHTTPServer(calculator: calculator, port: port)
		} else {
			// Use standard input/output
			runStdIO(calculator: calculator)
		}
	}
	
	/// Run the server using HTTP+SSE transport
	private func runHTTPServer(calculator: Calculator, port: Int) {
		// Create and start the HTTP SSE transport
		let transport = HTTPSSETransport(server: calculator, port: port)
		
		print("Starting HTTP server on port \(port)...")
		print("Press Ctrl+C to exit")
		
		// Add signal handler for SIGINT (Ctrl+C)
		signal(SIGINT) { _ in
			print("\nShutting down server...")
			Foundation.exit(0)
		}
		
		do {
			try transport.start()
		} catch {
			fputs("Error starting server: \(error.localizedDescription)\n", stderr)
			Foundation.exit(1)
		}
	}
	
	/// Run the server using stdin/stdout
	private func runStdIO(calculator: Calculator) {
		do {
			while true {
				if let input = readLine(),
				   !input.isEmpty,
				   let data = input.data(using: .utf8)
				{
					// fputs("\(input)\n", stderr)
					
					let request = try JSONDecoder().decode(SwiftMCP.JSONRPCRequest.self, from: data)
					
					
					// Handle the request
					if let response = calculator.handleRequest(request) {
						
						let data = try JSONEncoder().encode(response)
						let json = String(data: data, encoding: .utf8)!
						
						// Print the response and flush immediately
						print(json)
						fflush(stdout)
					}
				} else {
					// If no input is available, sleep briefly and try again
					Thread.sleep(forTimeInterval: 0.1)
				}
			}
		}
		catch
		{
			fputs("\(error.localizedDescription)\n", stderr)
		}
	}
}
