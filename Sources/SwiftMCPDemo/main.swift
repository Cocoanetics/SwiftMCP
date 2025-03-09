// SwiftMCP - Function Metadata Generator Demo
// A demonstration of using macros to generate JSON descriptions of functions

import Foundation
import SwiftMCP
import AnyCodable

// Create an instance of the Calculator
let calculator = Calculator()

// Create a request handler
let requestHandler = RequestHandler(calculator: calculator)

// MARK: - Main Loop

// Continue processing inputs
while true {
    if let input = readLineFromStdin(), let data = input.data(using: .utf8) {
        // Log the input for debugging
        logToStderr("Received input: \(input)")

        do {
            // Try to decode the JSON-RPC request
            let request = try JSONDecoder().decode(SwiftMCP.JSONRPCRequest.self, from: data)
            
            // Handle the request
            if let response = requestHandler.handleRequest(request) {
                sendResponse(response)
            }
        } catch {
            logToStderr("Failed to decode JSON-RPC request: \(error)")
        }
    } else {
        // If readLine() returns nil (EOF), sleep briefly and continue
        Thread.sleep(forTimeInterval: 0.1)
    }
} 