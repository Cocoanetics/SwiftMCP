#if canImport(Glibc)
@preconcurrency import Glibc
#endif

import Foundation
import AnyCodable

/**
 Protocol defining the interface for an MCP server.
 
 This protocol provides the core functionality required for an MCP (Model-Client Protocol) server.
 It is automatically implemented for classes or actors that are decorated with the `@MCPServer` macro.
 
 An MCP server provides:
 - Tool execution capabilities
 - Resource management
 - JSON-RPC message handling
 - Server metadata
 */
public protocol MCPServer {
    /**
     The name of the server.
     
     This name is used to identify the server in communications and logging.
     */
    var serverName: String { get }
    
    /**
     The version of the server.
     
     This version string helps clients understand the server's capabilities and compatibility.
     */
    var serverVersion: String { get }
    
    /**
     The description of the server.
     
     An optional description providing more details about the server's purpose and capabilities.
     */
    var serverDescription: String? { get }
    
    /**
     Handles a JSON-RPC request and generates an appropriate response.
     
     - Parameter request: The JSON-RPC request to handle
     - Returns: A response message if one should be sent, nil otherwise
     */
    func handleRequest(_ request: JSONRPCMessage) async -> JSONRPCMessage?
}

// MARK: - Default Implementations
public extension MCPServer {
    /**
     Default implementation for handling JSON-RPC requests.
     
     This implementation supports the following methods:
     - initialize: Server initialization
     - notifications/initialized: Client initialization notification
     - ping: Server health check
     - tools/list: List available tools
     - resources/list: List available resources
     - resources/templates/list: List available resource templates
     - resources/read: Read a specific resource
     - tools/call: Execute a tool
     
     - Parameter request: The JSON-RPC request to handle
     - Returns: A response message if one should be sent, nil otherwise
     */
    func handleRequest(_ request: JSONRPCMessage) async -> JSONRPCMessage? {
		
		guard case .request(let requestData) = request else {
			return nil
		}
		
        // Prepare the response based on the method
        switch requestData.method {
            case "initialize":
                return createInitializeResponse(id: requestData.id)
                
            case "notifications/initialized":
                return nil
				
			case "notifications/cancelled":
				return nil
                
            case "ping":
                return createPingResponse(id: requestData.id)
                
            case "tools/list":
                return createToolsListResponse(id: requestData.id)
                
            case "resources/list":
                return await createResourcesListResponse(id: requestData.id)
                
            case "resources/templates/list":
                return await createResourceTemplatesListResponse(id: requestData.id)
                
            case "resources/read":
                return await createResourcesReadResponse(id: requestData.id, request: requestData)
                
            case "tools/call":
                return await handleToolCall(requestData)
                
            default:
                // Respond with JSON-RPC error for method not found
                return JSONRPCMessage.errorResponse(id: requestData.id, error: .init(code: -32601, message: "Method not found"))
        }
    }
    
    /**
     Creates an initialization response for the server.
     
     The response includes:
     - Protocol version
     - Server capabilities
     - Server information
     
     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC message containing the initialization response
     */
    func createInitializeResponse(id: Int) -> JSONRPCMessage {
        var capabilities = ServerCapabilities()

        if self is MCPToolProviding {
            capabilities.tools = .init(listChanged: false)
        }

        if self is MCPResourceProviding {
            capabilities.resources = .init(listChanged: false)
        }

        let serverInfo = InitializeResult.ServerInfo(
            name: serverName,
            version: serverVersion
        )

        let result = InitializeResult(
            protocolVersion: "2024-11-05",
            capabilities: capabilities,
            serverInfo: serverInfo
        )

        do {
            let encoder = DictionaryEncoder()
            let resultDict = try encoder.encode(result)
            return JSONRPCMessage.response(id: id, result: resultDict)
        } catch {
            // Fallback to empty response if encoding fails
            return JSONRPCMessage.response(id: id, result: [:])
        }
    }
    
    /**
     Handles a tool execution request.
     
     - Parameter request: The JSON-RPC request containing the tool call details
     - Returns: A JSON-RPC message containing the tool execution result
     */
    private func handleToolCall(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
		
		guard let toolProvider = self as? MCPToolProviding else {
			return nil
		}
		
        guard let params = request.params,
              let toolName = params["name"]?.value as? String else {
            // Invalid request: missing tool name
            return nil
        }
        
        // Extract arguments from the request
        let arguments = (params["arguments"]?.value as? [String: Sendable]) ?? [:]
        
        // Call the appropriate wrapper method based on the tool name
        do {
            let result = try await toolProvider.callTool(toolName, arguments: arguments)
			
			let content: [String: Codable]
			
			if let resource = result as? MCPResourceContent {
				// Handle MCPResourceContent type
				content = [
					"type": "resource",
					"resource": resource
				]
			} else {
				let encoder = JSONEncoder()
				
				// Create ISO8601 formatter with timezone
				encoder.dateEncodingStrategy = .iso8601WithTimeZone
				
				let jsonData = try encoder.encode(result)
				let responseText = String(data: jsonData, encoding: .utf8) ?? ""
				
				content = [
					"type": "text",
					"text": responseText.removingQuotes
				]
			}
			
            return JSONRPCMessage.response(id: request.id, result: [
                "content": [content],
                "isError": false
            ])
            
        } catch {
            return JSONRPCMessage.response(id: request.id, result: [
                "content": [
                    ["type": "text", "text": error.localizedDescription]
                ],
                "isError": true
            ])
        }
    }
    
    /**
     The server's name, derived from the `@MCPServer` macro.
     */
    var serverName: String {
        Mirror(reflecting: self).children.first(where: { $0.label == "__mcpServerName" })?.value as? String ?? "UnknownServer"
    }
    
    /**
     The server's version, derived from the `@MCPServer` macro.
     */
    var serverVersion: String {
        Mirror(reflecting: self).children.first(where: { $0.label == "__mcpServerVersion" })?.value as? String ?? "UnknownVersion"
    }
    
    /**
     The server's description, derived from the `@MCPServer` macro.
     */
    var serverDescription: String? {
        Mirror(reflecting: self).children.first(where: { $0.label == "__mcpServerDescription" })?.value as? String
    }
	
	// MARK: - List Responses
	
	/**
	 Creates a response listing all available tools.
	 
	 - Parameter id: The request ID to include in the response
	 - Returns: A JSON-RPC message containing the tools list
	 */
	private func createToolsListResponse(id: Int) -> JSONRPCMessage {
		
		guard let toolProvider = self as? MCPToolProviding else
		{
			return JSONRPCMessage.response(id: id, result: [
				"content": [
					["type": "text", "text": "Server does not provide any tools"]
				],
				"isError": true
			])
		}
		
		return JSONRPCMessage.response(id: id, result: [
			"tools": AnyCodable(toolProvider.mcpToolMetadata.convertedToTools())
		])
	}
	
	/**
	 Creates a response listing all available resources.
	 
	 - Parameter id: The request ID to include in the response
	 - Returns: A JSON-RPC message containing the resources list
	 */
	func createResourcesListResponse(id: Int) async -> JSONRPCMessage {
		
		guard let resourceProvider = self as? MCPResourceProviding else
		{
			return JSONRPCMessage.response(id: id, result: [
				"content": [
					["type": "text", "text": "Server does not provide any resources"]
				],
				"isError": true
			])
		}
		
		/// get resources from templates that have no parameters plus developer provided array
		let resources = resourceProvider.mcpStaticResources + (await resourceProvider.mcpResources)
		
		let resourceDicts = resources.map { resource -> [String: Any] in
			return [
				"uri": resource.uri.absoluteString,
				"name": resource.name,
				"description": resource.description,
				"mimeType": resource.mimeType
			]
		}
		
		return JSONRPCMessage.response(id: id, result: ["resources": AnyCodable(resourceDicts)])
	}
    
    /**
     Creates a response for a resource read request.
     
     - Parameters:
       - id: The request ID to include in the response
       - request: The original JSON-RPC request
     - Returns: A JSON-RPC message containing the resource content or an error
     */
	func createResourcesReadResponse(id: Int, request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage {
		
		guard let resourceProvider = self as? MCPResourceProviding else
		{
			return JSONRPCMessage.response(id: id, result: [
				"content": [
					["type": "text", "text": "Server does not provide any resources"]
				],
				"isError": true
			])
		}
		
		// Extract the URI from the request params
		guard let uriString = request.params?["uri"]?.value as? String,
				  let uri = URL(string: uriString) else {
				return JSONRPCMessage.errorResponse(id: id, error: .init(code: -32602, message: "Invalid or missing URI parameter"))
			}
			
			do {
				// Try to get the resource content
				let resourceContentArray = try await resourceProvider.getResource(uri: uri)
				
				if !resourceContentArray.isEmpty
				{
					return JSONRPCMessage.response(id: id, result: ["contents": AnyCodable(resourceContentArray)])
				} else {
					return JSONRPCMessage.errorResponse(id: id, error: .init(code: -32001, message: "Resource not found: \(uri.absoluteString)"))
				}
			} catch {
				return JSONRPCMessage.errorResponse(id: id, error: .init(code: -32000, message: "Error getting resource: \(error.localizedDescription)"))
			}
		}
    
    /**
     Creates a response listing all available resource templates.
     
     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC response containing the resource templates list
     */
    func createResourceTemplatesListResponse(id: Int) async -> JSONRPCMessage {
		
		guard let resourceProvider = self as? MCPResourceProviding else
		{
			return JSONRPCMessage.response(id: id, result: [
				"content": [
					["type": "text", "text": "Server does not provide any resource templates"]
				],
				"isError": true
			])
		}
		
		let templates = await resourceProvider.mcpResourceTemplates

		return JSONRPCMessage.response(id: id, result: [
			"resourceTemplates": AnyCodable(templates.map { template in
				[
					"uriTemplate": template.uriTemplate,
					"name": template.name,
					"description": template.description,
					"mimeType": template.mimeType
				]
			})
		])
	}
    
    /**
     Creates a ping response with empty result.
     
     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC response for ping
     */
    func createPingResponse(id: Int) -> JSONRPCMessage {
        return JSONRPCMessage.response(id: id, result: [:])
    }
    
	// MARK: - Internal Helpers
	
	/**
	 Provides metadata for a function annotated with `@MCPTool`.
	 
	 - Parameter toolName: The name of the tool
	 - Returns: The metadata for the tool
	 
	 This property uses runtime reflection to gather tool metadata from properties
	 generated by the `@MCPTool` macro.
	 */
	func mcpToolMetadata(for toolName: String) -> MCPToolMetadata?
	{
		let metadataKey = "__mcpMetadata_\(toolName)"
		
		// Find the metadata for the function using reflection
		let mirror = Mirror(reflecting: self)
		guard let child = mirror.children.first(where: { $0.label == metadataKey }),
			  let metadata = child.value as? MCPToolMetadata else {
			return nil
		}
		
		return metadata
	}
}
