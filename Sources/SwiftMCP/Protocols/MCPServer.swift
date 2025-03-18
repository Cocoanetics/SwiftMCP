import Foundation
import AnyCodable

/// Protocol defining the requirements for an MCP server
public protocol MCPServer: AnyObject {
    /// Returns an array of all MCP tools defined in this type
    var mcpTools: [MCPTool] { get }
    
    /// Returns an array of all MCP resources defined in this type
    var mcpResources: [MCPResource] { get }
	
	/// Returns an array of all MCP resource templates defined in this type
	var mcpResourceTemplates: [MCPResourceTemplate] { get }

    
    /// Calls a tool by name with the provided arguments
    /// - Parameters:
    ///   - name: The name of the tool to call
    ///   - arguments: A dictionary of arguments to pass to the tool
    /// - Returns: The result of the tool call
    /// - Throws: MCPToolError if the tool doesn't exist or cannot be called
    func callTool(_ name: String, arguments: [String: Any]) async throws -> Codable
    
    /// Gets a resource by URI
    /// - Parameter uri: The URI of the resource to get
    /// - Returns: The resource content, or nil if the resource doesn't exist
    /// - Throws: MCPResourceError if there's an error getting the resource
    func getResource(uri: URL) throws -> MCPResourceContent?
    
    /// Handles a JSON-RPC request
    /// - Parameter request: The JSON-RPC request to handle
    /// - Returns: The response as a string, or nil if no response should be sent
    func handleRequest(_ request: JSONRPCRequest) async -> Codable?
}

public enum MCPResourceKind
{
	case text(String)
	
	case data(Data)
}

// MARK: - Default Implementations
public extension MCPServer {
    /// Handles a JSON-RPC request with default implementation
    /// - Parameter request: The JSON-RPC request to handle
    /// - Returns: A JSON-RPC reesponse, or `nil` if no response is necessary
    func handleRequest(_ request: JSONRPCRequest) async -> Codable? {
        // Prepare the response based on the method
        switch request.method {
            case "initialize":
				
                return createInitializeResponse(id: request.id ?? 0)
                
            case "notifications/initialized":
                return nil
                
            case "ping":
                return createPingResponse(id: request.id ?? 0)
                
            case "tools/list":
                return createToolsResponse(id: request.id ?? 0)
                
            case "resources/list":
                return createResourcesListResponse(id: request.id ?? 0)
                
            case "resources/templates/list":
                return createResourceTemplatesListResponse(id: request.id ?? 0)
                
            case "resources/read":
                return createResourcesReadResponse(id: request.id ?? 0, request: request)
                
            case "tools/call":
                return await handleToolCall(request)
                
            default:
                return nil
        }
    }
    
    /// Creates a default initialize response
    /// - Parameter id: The request ID
    /// - Returns: The initialize response
    func createInitializeResponse(id: Int) -> JSONRPC.Response {
        let responseDict: [String: Any] = [
            "protocolVersion": "2024-11-05",
            "capabilities": [
                "experimental": [:],
				"resources": ["listChanged": false],
                "tools": ["listChanged": false]
            ],
            "serverInfo": [
                "name": serverName,
                "version": serverVersion
            ]
        ]

        return JSONRPC.Response(id: .number(id), result: .init(responseDict))
    }
    
    /// Creates a resources list response
    /// - Parameter id: The request ID
    /// - Returns: The resources list response
    func createResourcesListResponse(id: Int) -> JSONRPC.Response {
        // Convert MCPResource objects to dictionaries
        let resourceDicts = mcpResources.map { resource -> [String: Any] in
            return [
                "uri": resource.uri.absoluteString,
                "name": resource.name,
                "description": resource.description,
                "mimeType": resource.mimeType
            ]
        }
        
        let resourcesList: [String: Any] = [
			"resources": resourceDicts
        ]
        
        return JSONRPC.Response(id: .number(id), result: .init(resourcesList))
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
    private func handleToolCall(_ request: JSONRPCRequest) async -> Codable? {
        guard let params = request.params,
              let toolName = params["name"]?.value as? String else {
            // Invalid request: missing tool name
            return nil
        }
        
        // Extract arguments from the request
        let arguments = (params["arguments"]?.value as? [String: Any]) ?? [:]
        
        // Call the appropriate wrapper method based on the tool name
        do {
            let result = try await self.callTool(toolName, arguments: arguments)
			let responseText = "\(result)"
			
			return ToolCallResponse(id: request.id ?? 0, result: responseText)
			
		} catch {
			
			return ToolCallResponse(id: request.id ?? 0, error: error)
        }
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
    
    var serverName: String {
        Mirror(reflecting: self).children.first(where: { $0.label == "__mcpServerName" })?.value as? String ?? "UnknownServer"
    }
    
    var serverVersion: String {
        Mirror(reflecting: self).children.first(where: { $0.label == "__mcpServerVersion" })?.value as? String ?? "UnknownVersion"
    }
	
	var serverDescription: String? {
		Mirror(reflecting: self).children.first(where: { $0.label == "__mcpServerDescription" })?.value as? String
	}
    
    /// Creates a resources read response
    /// - Parameters:
    ///   - id: The request ID
    ///   - request: The original JSON-RPC request
    /// - Returns: The resources read response
    func createResourcesReadResponse(id: Int, request: JSONRPCRequest) -> JSONRPC.Response {
        // Extract the URI from the request params
        guard let uriString = request.params?["uri"]?.value as? String,
              let uri = URL(string: uriString) else {
            // If no URI is provided or it's invalid, return an error
            let errorDict: [String: Any] = [
                "error": "Invalid or missing URI parameter"
            ]
            return JSONRPC.Response(id: .number(id), result: .init(errorDict))
        }
        
        do {
            // Try to get the resource content
            if let resourceContent = try getResource(uri: uri) {
                // Convert MCPResourceContent to dictionary
                var contentDict: [String: Any] = [
                    "uri": resourceContent.uri.absoluteString
                ]
                
                // Add optional fields if they exist
                if let mimeType = resourceContent.mimeType {
                    contentDict["mimeType"] = mimeType
                }
                
                if let text = resourceContent.text {
                    contentDict["text"] = text
                }
                
                if let blob = resourceContent.blob {
                    // Convert binary data to base64 string
                    contentDict["blob"] = blob.base64EncodedString()
                }
                
                // Create the response
                let responseDict: [String: Any] = [
                    "contents": [contentDict]
                ]
                
                return JSONRPC.Response(id: .number(id), result: .init(responseDict))
            } else {
                // Resource not found
                let errorDict: [String: Any] = [
                    "error": "Resource not found: \(uri.absoluteString)"
                ]
                return JSONRPC.Response(id: .number(id), result: .init(errorDict))
            }
        } catch {
            // Error getting resource
            let errorDict: [String: Any] = [
                "error": "Error getting resource: \(error.localizedDescription)"
            ]
            return JSONRPC.Response(id: .number(id), result: .init(errorDict))
        }
    }
    
    /// Creates a resource templates list response
    /// - Parameter id: The request ID
    /// - Returns: The resource templates list response
    func createResourceTemplatesListResponse(id: Int) -> JSONRPC.Response {
        // Convert MCPResourceTemplate objects to dictionaries
        let templateDicts = mcpResourceTemplates.map { template -> [String: Any] in
            return [
                "uriTemplate": template.uriTemplate.absoluteString,
                "name": template.name,
                "description": template.description,
                "mimeType": template.mimeType
            ]
        }
        
        let templatesResponse: [String: Any] = [
            "resourceTemplates": templateDicts
        ]
        
        return JSONRPC.Response(id: .number(id), result: .init(templatesResponse))
    }
    
    /// Creates a ping response
    /// - Parameter id: The request ID
    /// - Returns: The ping response
    func createPingResponse(id: Int) -> JSONRPC.Response {
        // Create an empty result object
        let emptyResult: [String: Any] = [:]
        
        // Return a response with the empty result
        return JSONRPC.Response(id: .number(id), result: .init(emptyResult))
    }
    
    /// Default implementation for mcpResources
    var mcpResources: [MCPResource] {
        // By default, return an empty array
        // Implementations can override this to provide actual resources
        return []
    }
	
	/// Default implementation for mcpResources
	var mcpResourceTemplates: [MCPResourceTemplate] {
		// By default, return an empty array
		// Implementations can override this to provide actual resources
		return []
	}

	/// Default implementation
	func getResource(uri: URL) throws -> MCPResourceContent? {
		return nil
	}
    
    /// The name of the server
    var name: String {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.label == "__mcpServerName" {
                return child.value as? String ?? "UnnamedServer"
            }
        }
        return "UnnamedServer"
    }
    
    /// The version of the server
    var version: String {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.label == "__mcpServerVersion" {
                return child.value as? String ?? "1.0"
            }
        }
        return "1.0"
    }
    
    /// The description of the server from its documentation
    var description: String? {
        let mirror = Mirror(reflecting: self)
        for child in mirror.children {
            if child.label == "__mcpServerDescription" {
                return child.value as? String
            }
        }
        return nil
    }
}
