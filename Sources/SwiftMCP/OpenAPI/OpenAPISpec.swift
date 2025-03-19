import Foundation

/// Represents an OpenAPI 3.1.0 specification
public struct OpenAPISpec: Codable {
    /// Basic information about the API
    public struct Info: Codable {
        public let title: String
        public let version: String
        public let description: String
    }
    
    /// Server information
    public struct Server: Codable {
        public let url: String
        public let description: String
    }
    
    /// Request or response content
    public struct Content: Codable {
        public let schema: JSONSchema
    }
    
    /// Request body specification
    public struct RequestBody: Codable {
        public let required: Bool
        public let content: [String: Content]
    }
    
    /// Response specification
    public struct Response: Codable {
        public let description: String
        public let content: [String: Content]?
    }
    
    /// Operation (e.g., POST) specification
    public struct Operation: Codable {
        public let summary: String
        public let operationId: String
        public let description: String
        public let requestBody: RequestBody?
        public let responses: [String: Response]
    }
    
    /// Path item specification
    public struct PathItem: Codable {
        public let post: Operation?
    }
    
    public let openapi: String
    public let info: Info
    public let servers: [Server]
    public let paths: [String: PathItem]
    
    /// Creates an OpenAPI specification for an MCP server
    /// - Parameters:
    ///   - server: The MCP server to create the spec for
    ///   - host: The host where the server is running
    ///   - port: The port where the server is running
	public init(server: MCPServer, scheme: String, host: String) {
        self.openapi = "3.1.0"
        self.info = Info(
            title: "\(server.name) API",
            version: server.version,
            description: server.description ?? "API for \(server.name) providing various tools."
        )
        
        self.servers = [
            Server(
                url: "\(scheme)://\(host)",
                description: "Production Server"
            )
        ]
        
        // Create paths from server tools
        var paths: [String: PathItem] = [:]
		
		let rootPath = server.name.asModelName
        
        for tool in server.mcpTools {
            let pathKey = "/\(rootPath)/\(tool.name)"
            
            // Get the metadata for this tool using reflection
            let metadataKey = "__mcpMetadata_\(tool.name)"
            let mirror = Mirror(reflecting: server)
            let metadata = mirror.children.first(where: { $0.label == metadataKey })?.value as? MCPToolMetadata
            
            // Create response schema (default to string since we don't have return type info)
            // For Void return type, we still use string schema but indicate it returns empty string
            let responseSchema = if metadata?.returnType == "Void" {
                JSONSchema.string(description: "Empty string (void function)")
            } else {
                JSONSchema.string()
            }
            
            // Create error response schema to match {"error": "error message"}
            let errorSchema = JSONSchema.object(
                properties: [
                    "error": .string()  // No description needed as it will contain error.localizedDescription
                ],
                required: ["error"],
                description: "Error response containing the error message"
            )
            
            // Create responses dictionary with success and error cases
            var responses: [String: Response] = [
                "200": Response(
                    description: metadata?.returnTypeDescription ?? "Successful response",
                    content: [
                        "application/json": Content(schema: responseSchema)
                    ]
                )
            ]
            
            // Add error response if the function can throw
            if metadata?.isThrowing ?? false {
                responses["400"] = Response(
                    description: "The function threw an error",
                    content: [
                        "application/json": Content(schema: errorSchema)
                    ]
                )
            }
            
            // Create the path item
            let pathItem = PathItem(
                post: Operation(
                    summary: tool.name,
                    operationId: tool.name,
                    description: tool.description ?? "No description available",
                    requestBody: RequestBody(
                        required: true, // If it's a tool, the request body is always required
                        content: [
                            "application/json": Content(schema: tool.inputSchema)
                        ]
                    ),
                    responses: responses
                )
            )
            
            paths[pathKey] = pathItem
        }
        
        self.paths = paths
    }
} 
