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
        
        // Process inputs in a loop
        processInputs(server: calculator)
    }
    
    /// Process inputs in a continuous loop
    private func processInputs(server: MCPServer) {
        // Continue processing inputs
        while true {
            if let input = readLine() {
				
				logToStderr("Received: \(input)")
                if !input.isEmpty, let data = input.data(using: .utf8) {
                    processJSONRPCRequest(data: data, server: server)
                }
            } else {
                // If no input is available, sleep briefly and try again
                Thread.sleep(forTimeInterval: 0.1)
            }
        }
    }
    
    /// Process a JSON-RPC request
    private func processJSONRPCRequest(data: Data, server: MCPServer) {
        do {
            // Try to decode the JSON-RPC request
            let request = try JSONDecoder().decode(SwiftMCP.JSONRPCRequest.self, from: data)
            
            // Handle the request
            if let response = server.handleRequest(request) {
                // Print the response and flush immediately
                print(response)
                fflush(stdout)
				
				logToStderr("Replied: \(response)")
            }
        } catch {
            logToStderr("Failed to decode JSON-RPC request: \(error)")
        }
    }
    
    /// Log a message to stderr
    private func logToStderr(_ message: String) {
        fputs("\(message)\n", stderr)
    }
} 
