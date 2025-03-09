import Foundation
import SwiftMCP

// MARK: - Utility Functions

/// Function to read a line from stdin
func readLineFromStdin() -> String? {
    return readLine(strippingNewline: true)
}

/// Function to send a response to stdout
func sendResponse(_ response: String) {
    print(response)
    fflush(stdout) // Ensure the output is flushed immediately
}

/// Function to log a message to stderr
func logToStderr(_ message: String) {
    let stderr = FileHandle.standardError
    if let data = (message + "\n").data(using: .utf8) {
        stderr.write(data)
    }
}

/// Creates a tools list response using the mcpTools from the provided object
func createToolsListResponse(id: Int, from object: Any) -> ToolsListResponse {
    // Get the mcpTools using reflection
    var tools: [MCPTool] = []
    
    if let calculator = object as? Calculator {
        tools = calculator.mcpTools
    }
    
    // Create and return the response
    return ToolsListResponse(
        jsonrpc: "2.0",
        id: id,
        result: .init(tools: tools)
    )
} 