import Foundation
import ArgumentParser
import SwiftMCP
import AnyCodable

/// Command-line interface for the SwiftMCP demo
@main
struct MCPCommand: ParsableCommand {
	static var configuration = CommandConfiguration(
		commandName: "mcp",
		abstract: "A utility for testing SwiftMCP functions",
		discussion: """
  Process JSON-RPC requests for SwiftMCP functions.
  
  The command reads JSON-RPC requests from stdin and writes responses to stdout.
  """
	)
	
	/// The main entry point for the command
	func run() throws {
		// Create an instance of the Calculator
		let calculator = Calculator()
		
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
