import Foundation
import SwiftMCP
import AnyCodable

/// Handles JSON-RPC requests
class RequestHandler {
    /// The calculator instance
    private let calculator: Calculator
    
    /// Initializes a new request handler with a calculator
    init(calculator: Calculator) {
        self.calculator = calculator
    }
    
    /// Handles a JSON-RPC request
    /// - Parameter request: The JSON-RPC request to handle
    /// - Returns: The response as a string, or nil if no response should be sent
    func handleRequest(_ request: SwiftMCP.JSONRPCRequest) -> String? {
        // Prepare the response based on the method
        switch request.method {
            case "initialize":
                let response = InitializeResponse.createDefault(id: request.id)
                let encodedResponse = try! JSONEncoder().encode(response)
                return String(data: encodedResponse, encoding: .utf8)!
                
            case "notifications/initialized":
                return nil
                
            case "tools/list":
                let response = createToolsListResponse(id: request.id, from: calculator)
                let encodedResponse = try! JSONEncoder().encode(response)
                return String(data: encodedResponse, encoding: .utf8)!
                
            case "tools/call":
                return handleToolCall(request)
                
            default:
                return nil
        }
    }
    
    /// Handles a tool call request
    /// - Parameter request: The JSON-RPC request for a tool call
    /// - Returns: The response as a string, or nil if no response should be sent
    private func handleToolCall(_ request: SwiftMCP.JSONRPCRequest) -> String? {
        guard let params = request.params,
              let toolName = params["name"]?.value as? String else {
            // Invalid request: missing tool name
            return nil
        }
        
        // Get the arguments and prepare response text
        var responseText = ""
        var isError = false
        
        // Extract arguments from the request
        let arguments = (params["arguments"]?.value as? [String: Any]) ?? [:]
        
        // Call the appropriate wrapper method based on the tool name
        do {
            let result = try calculator.callTool(toolName, arguments: arguments)
            responseText = "\(result)"
        } catch let error as MCPToolError {
            responseText = error.description
            isError = true
        } catch {
            responseText = "Error: \(error)"
            isError = true
        }
        
        // Create and encode the response
        let response = ToolCallResponse(id: request.id, text: responseText, isError: isError)
        let encodedResponse = try! JSONEncoder().encode(response)
        return String(data: encodedResponse, encoding: .utf8)!
    }
} 