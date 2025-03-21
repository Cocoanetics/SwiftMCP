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
     The tools available on this server.
     
     Tools are functions that can be called remotely through the MCP protocol.
     Each tool has a name, description, and set of parameters it accepts.
     */
    var mcpTools: [MCPTool] { get }
    
    /**
     The resources available on this server.
     
     Resources are data objects that can be accessed through the MCP protocol.
     Each resource has a URI, name, description, and MIME type.
     */
    var mcpResources: [MCPResource] { get async }
    
    /**
     The resource templates available on this server.
     
     Resource templates define patterns for resources that can be dynamically created
     or accessed. Each template has a URI pattern, name, description, and MIME type.
     */
    var mcpResourceTemplates: [MCPResourceTemplate] { get async }
    
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
     Retrieves a resource by its URI.
     
     - Parameter uri: The URI of the resource to retrieve
     - Returns: The resource content if found, nil otherwise
     - Throws: An error if the resource cannot be accessed
     */
    func getResource(uri: URL) async throws -> MCPResourceContent?
    
    /**
     Calls a tool by name with the provided arguments.
     
     - Parameters:
       - name: The name of the tool to call
       - arguments: The arguments to pass to the tool
     - Returns: The result of the tool execution
     - Throws: An error if the tool execution fails
     */
    func callTool(_ name: String, arguments: [String: Sendable]) async throws -> Sendable & Codable
    
    /**
     Handles a JSON-RPC request and generates an appropriate response.
     
     - Parameter request: The JSON-RPC request to handle
     - Returns: A response message if one should be sent, nil otherwise
     */
    func handleRequest(_ request: JSONRPCMessage) async -> JSONRPCMessage?
}

/**
 Represents the kind of content a resource can provide.
 
 Resources can provide either textual or binary data:
 - text: Plain text content
 - data: Binary data content
 */
public enum MCPResourceKind
{
	case text(String)
	
	case data(Data)
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
    
    /**
     Creates a response listing all available resources.
     
     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC message containing the resources list
     */
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
    
    /**
     Creates a response listing all available tools.
     
     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC message containing the tools list
     */
    private func createToolsResponse(id: Int) -> JSONRPCMessage {
        var response = JSONRPCMessage()
        response.id = id
        response.result = [
            "tools": AnyCodable(mcpTools)
        ]
        return response
    }
    
    /**
     Handles a tool execution request.
     
     - Parameter request: The JSON-RPC request containing the tool call details
     - Returns: A JSON-RPC message containing the tool execution result
     */
    private func handleToolCall(_ request: JSONRPCMessage) async -> JSONRPCMessage? {
        guard let params = request.params,
              let toolName = params["name"]?.value as? String else {
            // Invalid request: missing tool name
            return nil
        }
        
        // Extract arguments from the request
        let arguments = (params["arguments"]?.value as? [String: Sendable]) ?? [:]
        
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
    
    /**
     Logs a message to standard error.
     
     - Parameter message: The message to log
     */
//    func logToStderr(_ message: String) {
//        let stderr = FileHandle.standardError
//        if let data = (message + "\n").data(using: .utf8) {
//            stderr.write(data)
//        }
//    }
    
    /**
     Sends a response to standard output.
     
     - Parameter response: The response string to send
     */
//    func sendResponse(_ response: String) async throws {
//       try await AsyncOutput.shared.writeToStdout(response)
//    }
    
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
    
    /**
     Creates a response for a resource read request.
     
     - Parameters:
       - id: The request ID to include in the response
       - request: The original JSON-RPC request
     - Returns: A JSON-RPC message containing the resource content or an error
     */
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
    
    /**
     Creates a response listing all available resource templates.
     
     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC message containing the resource templates list
     */
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
    
    /**
     Creates a response to a ping request.
     
     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC message acknowledging the ping
     */
    func createPingResponse(id: Int) -> JSONRPCMessage {
        var response = JSONRPCMessage()
        response.id = id
        response.result = [:]
        return response
    }
    
    /**
     Default implementation providing an empty list of resources.
     
     Override this property to provide actual resources.
     */
    var mcpResources: [MCPResource] {
        // By default, return an empty array
        // Implementations can override this to provide actual resources
        return []
    }
    
    /**
     Default implementation providing an empty list of resource templates.
     
     Override this property to provide actual resource templates.
     */
    var mcpResourceTemplates: [MCPResourceTemplate] {
        // By default, return an empty array
        // Implementations can override this to provide actual resources
        return []
    }
    
    /**
     Default implementation for resource retrieval.
     
     Override this method to provide actual resource content.
     
     - Parameter uri: The URI of the resource to retrieve
     - Returns: nil, indicating no resources are available
     */
    func getResource(uri: URL) async throws -> MCPResourceContent? {
        return nil
    }
    
    /**
     Provides metadata for all functions annotated with `@MCPTool`.
     
     This property uses runtime reflection to gather tool metadata from properties
     generated by the `@MCPTool` macro.
     */
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
    
    /**
     Converts tool metadata into MCP tool descriptions.
     
     This property transforms the metadata from `@MCPTool` annotations into
     a format suitable for tool discovery and documentation.
     */
    var mcpTools: [MCPTool] {
        return mcpToolMetadata.convertedToTools()
    }
}
