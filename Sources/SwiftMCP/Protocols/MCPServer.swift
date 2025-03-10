import Foundation
import AnyCodable

/// Protocol defining the requirements for an MCP server
public protocol MCPServer {
    /// Returns an array of all MCP tools defined in this type
    var mcpTools: [MCPTool] { get }
    
    /// Calls a tool by name with the provided arguments
    /// - Parameters:
    ///   - name: The name of the tool to call
    ///   - arguments: A dictionary of arguments to pass to the tool
    /// - Returns: The result of the tool call
    /// - Throws: MCPToolError if the tool doesn't exist or cannot be called
    func callTool(_ name: String, arguments: [String: Any]) throws -> Any
    
    /// Handles a JSON-RPC request
    /// - Parameter request: The JSON-RPC request to handle
    /// - Returns: The response as a string, or nil if no response should be sent
    func handleRequest(_ request: JSONRPCRequest) -> String?
}

// MARK: - Default Implementations
public extension MCPServer {
    /// Handles a JSON-RPC request with default implementation
    /// - Parameter request: The JSON-RPC request to handle
    /// - Returns: The response as a string, or nil if no response should be sent
    func handleRequest(_ request: JSONRPCRequest) -> String? {
        // Prepare the response based on the method
        switch request.method {
            case "initialize":
                let response = createInitializeResponse(id: request.id)
                let encodedResponse = try! JSONEncoder().encode(response)
                return String(data: encodedResponse, encoding: .utf8)!
                
            case "notifications/initialized":
                return nil
                
            case "tools/list":
                let response = createToolsResponse(id: request.id)
                let encodedResponse = try! JSONEncoder().encode(response)
                return String(data: encodedResponse, encoding: .utf8)!
                
            case "tools/call":
                return handleToolCall(request)
                
            default:
                return nil
        }
    }
    
    /// Creates a default initialize response
    /// - Parameter id: The request ID
    /// - Returns: The initialize response
    private func createInitializeResponse(id: Int) -> JSONRPC.Response {
        let serverInfo = MCPServerInfo(
            name: "SwiftMCP",
            version: "1.0.0"
        )
        
        let result = MCPCapabilitiesResult(
            protocol_version: "0.1.0",
            capabilities: MCPCapabilities(tools: mcpTools),
            server_info: serverInfo,
            instructions: "Welcome to SwiftMCP!"
        )
        
        return JSONRPC.Response(id: .number(id), result: .init(result))
    }
    
    /// Creates a tools response
    /// - Parameter id: The request ID
    /// - Returns: The tools response
    private func createToolsResponse(id: Int) -> ToolsResponse {
        return ToolsResponse(
            jsonrpc: "2.0",
            id: id,
            result: .init(tools: mcpTools)
        )
    }
    
    /// Handles a tool call request
    /// - Parameter request: The JSON-RPC request for a tool call
    /// - Returns: The response as a string, or nil if no response should be sent
    private func handleToolCall(_ request: JSONRPCRequest) -> String? {
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
            let result = try self.callTool(toolName, arguments: arguments)
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
    
    /// Function to log a message to stderr
    func logToStderr(_ message: String) {
        let stderr = FileHandle.standardError
        if let data = (message + "\n").data(using: .utf8) {
            stderr.write(data)
        }
    }
    
    /// Function to send a response to stdout
    func sendResponse(_ response: String) {
        fputs(response + "\n", stdout)
        fflush(stdout) // Ensure the output is flushed immediately
    }
} 
