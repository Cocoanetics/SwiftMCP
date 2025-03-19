import Foundation
import AnyCodable

/// Protocol defining the interface for an MCP server
public protocol MCPServer: Sendable {
    /// The tools available on this server
    var mcpTools: [MCPTool] { get }
    
    /// The resources available on this server
    var mcpResources: [MCPResource] { get async }
    
    /// The resource templates available on this server
    var mcpResourceTemplates: [MCPResourceTemplate] { get async }
    
    /// The name of the server
    var name: String { get }
    
    /// The version of the server
    var version: String { get }
    
    /// The description of the server
    var serverDescription: String? { get }
    
    /// Get a resource by its URI
    /// - Parameter uri: The URI of the resource to get
    /// - Returns: The resource content, or nil if not found
    func getResource(uri: URL) async throws -> MCPResourceContent?
    
    /// Call a tool by name with arguments
    /// - Parameters:
    ///   - name: The name of the tool to call
    ///   - arguments: The arguments to pass to the tool
    /// - Returns: The result of the tool call
    func callTool(_ name: String, arguments: [String: Any]) async throws -> Codable
    
    /// Handle a JSON-RPC request
    /// - Parameter request: The JSON-RPC request to handle
    /// - Returns: The response as a string, or nil if no response should be sent
    func handleRequest(_ request: JSONRPCMessage) async -> JSONRPCMessage?
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
    /// - Returns: A JSON-RPC response, or `nil` if no response is necessary
    func handleRequest(_ request: JSONRPCMessage) async -> JSONRPCMessage? {
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
                return await createResourcesListResponse(id: request.id ?? 0)
                
            case "resources/templates/list":
                return await createResourceTemplatesListResponse(id: request.id ?? 0)
                
            case "resources/read":
                return await createResourcesReadResponse(id: request.id ?? 0, request: request)
                
            case "tools/call":
                return await handleToolCall(request)
                
            default:
                return nil
        }
    }
    
    /// Creates a default initialize response
    /// - Parameter id: The request ID
    /// - Returns: The initialize response
    func createInitializeResponse(id: Int) -> JSONRPCMessage {
        var response = JSONRPCMessage()
        response.id = id
        response.result = [
            "protocolVersion": AnyCodable("2024-11-05"),
            "capabilities": AnyCodable([
                "experimental": [:],
                "resources": ["listChanged": false],
                "tools": ["listChanged": false]
            ] as [String: Any]),
            "serverInfo": AnyCodable([
                "name": serverName,
                "version": serverVersion
            ] as [String: Any])
        ]
        return response
    }
    
    /// Creates a resources list response
    /// - Parameter id: The request ID
    /// - Returns: The resources list response
    func createResourcesListResponse(id: Int) async -> JSONRPCMessage {
        let resourceDicts = await mcpResources.map { resource -> [String: Any] in
            return [
                "uri": resource.uri.absoluteString,
                "name": resource.name,
                "description": resource.description,
                "mimeType": resource.mimeType
            ]
        }
        
        var response = JSONRPCMessage()
        response.id = id
        response.result = [
            "resources": AnyCodable(resourceDicts)
        ]
        return response
    }
    
    /// Creates a tools response
    /// - Parameter id: The request ID
    /// - Returns: The tools response
    private func createToolsResponse(id: Int) -> JSONRPCMessage {
        var response = JSONRPCMessage()
        response.id = id
        response.result = [
            "tools": AnyCodable(mcpTools)
        ]
        return response
    }
    
    /// Handles a tool call request
    /// - Parameter request: The JSON-RPC request for a tool call
    /// - Returns: The response as a string, or nil if no response should be sent
	private func handleToolCall(_ request: JSONRPCMessage) async -> JSONRPCMessage? {
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
			let responseText: String
			
			// Use Mirror to check if the result is Void
			let mirror = Mirror(reflecting: result)
			if mirror.displayStyle == .tuple && mirror.children.isEmpty {
				responseText = ""  // Convert Void to empty string
			} else {
				responseText = "\(result)"
			}
			
			var response = JSONRPCMessage()
			response.jsonrpc = "2.0"
			response.id = request.id
			response.result = [
				"content": AnyCodable([
					["type": "text", "text": responseText]
				]),
				"isError": AnyCodable(false)
			]
			return response
			
		} catch {
			var response = JSONRPCMessage()
			response.jsonrpc = "2.0"
			response.id = request.id
			response.result = [
				"content": AnyCodable([
					["type": "text", "text": error.localizedDescription]
				]),
				"isError": AnyCodable(true)
			]
			return response
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
    func createResourcesReadResponse(id: Int, request: JSONRPCMessage) async -> JSONRPCMessage {
        // Extract the URI from the request params
        guard let uriString = request.params?["uri"]?.value as? String,
              let uri = URL(string: uriString) else {
            var response = JSONRPCMessage()
            response.id = id
            response.error = .init(code: -32602, message: "Invalid or missing URI parameter")
            return response
        }
        
        do {
            // Try to get the resource content
            if let resourceContent = try await getResource(uri: uri) {
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
                
                var response = JSONRPCMessage()
                response.id = id
                response.result = [
                    "contents": AnyCodable([contentDict])
                ]
                return response
                
            } else {
                var response = JSONRPCMessage()
                response.id = id
                response.error = .init(code: -32001, message: "Resource not found: \(uri.absoluteString)")
                return response
            }
        } catch {
            var response = JSONRPCMessage()
            response.id = id
            response.error = .init(code: -32000, message: "Error getting resource: \(error.localizedDescription)")
            return response
        }
    }
    
    /// Creates a resource templates list response
    /// - Parameter id: The request ID
    /// - Returns: The resource templates list response
    func createResourceTemplatesListResponse(id: Int) async -> JSONRPCMessage {
        let templateDicts = await mcpResourceTemplates.map { template -> [String: Any] in
            return [
                "uriTemplate": template.uriTemplate.absoluteString,
                "name": template.name,
                "description": template.description,
                "mimeType": template.mimeType
            ]
        }
        
        var response = JSONRPCMessage()
        response.id = id
        response.result = [
            "resourceTemplates": AnyCodable(templateDicts)
        ]
        return response
    }
    
    /// Creates a ping response
    /// - Parameter id: The request ID
    /// - Returns: The ping response
    func createPingResponse(id: Int) -> JSONRPCMessage {
        var response = JSONRPCMessage()
        response.id = id
        response.result = [:]
        return response
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
	func getResource(uri: URL) async throws -> MCPResourceContent? {
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

	/// Function to provide the metadata for all functions annotated with @MCPTool
	var mcpToolMetadata: [MCPToolMetadata]  {
		var metadataArray: [MCPToolMetadata] = []
		let mirror = Mirror(reflecting: self)
		
		for child in mirror.children {
			if let metadata = child.value as? MCPToolMetadata,
			   child.label?.hasPrefix("__mcpMetadata_") == true {
				metadataArray.append(metadata)
			}
		}
		
		return metadataArray
	}
	
	/// Returns an array of all MCP tools defined in this type
	var mcpTools: [MCPTool] {
	   return mcpToolMetadata.convertedToTools()
	}
}
