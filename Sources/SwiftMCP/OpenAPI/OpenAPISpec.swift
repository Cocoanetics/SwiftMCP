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
        let rootPath = server.name.asModelName
        var paths: [String: PathItem] = [:]
        
        for metadata in server.mcpToolMetadata {
            let pathKey = "/\(rootPath)/\(metadata.name)"
            
            // Create response schema based on return type
            let responseSchema: JSONSchema
            let responseDescription: String
            let voidDescription = "Empty string (void function)"
            
            if metadata.returnType == nil || metadata.returnType == "Void" {
                responseSchema = .string(description: voidDescription)
                responseDescription = metadata.returnTypeDescription ?? "A void function that performs an action"
            } else {
                // Convert Swift type to JSON Schema type
                let returnType = metadata.returnType ?? "String"
                switch returnType.JSONSchemaType {
                    case "number":
                        responseSchema = .number(description: metadata.returnTypeDescription)
                    case "boolean":
                        responseSchema = .boolean(description: metadata.returnTypeDescription)
                    case "array":
                        if let elementType = returnType.arrayElementType {
                            let itemSchema: JSONSchema
                            switch elementType.JSONSchemaType {
                                case "number":
                                    itemSchema = .number()
                                case "boolean":
                                    itemSchema = .boolean()
                                default:
                                    itemSchema = .string()
                            }
                            responseSchema = .array(items: itemSchema, description: metadata.returnTypeDescription)
                        } else {
                            responseSchema = .array(items: .string(), description: metadata.returnTypeDescription)
                        }
                    default:
                        responseSchema = .string(description: metadata.returnTypeDescription)
                }
                responseDescription = metadata.returnTypeDescription ?? "The returned value of the tool"
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
                    description: responseDescription,
                    content: [
                        "application/json": Content(schema: responseSchema)
                    ]
                )
            ]
            
            // Add error response if the function can throw
            if metadata.isThrowing {
                responses["400"] = Response(
                    description: "The function threw an error",
                    content: [
                        "application/json": Content(schema: errorSchema)
                    ]
                )
            }
            
            // Create input schema from parameters
            let inputSchema = JSONSchema.object(
                properties: metadata.parameters.reduce(into: [:]) { dict, param in
                    let paramType = param.type.JSONSchemaType
                    switch paramType {
                        case "number":
                            dict[param.name] = .number(description: param.description)
                        case "boolean":
                            dict[param.name] = .boolean(description: param.description)
                        case "array":
                            if let elementType = param.type.arrayElementType {
                                let itemSchema: JSONSchema
                                switch elementType.JSONSchemaType {
                                    case "number":
                                        itemSchema = .number()
                                    case "boolean":
                                        itemSchema = .boolean()
                                    default:
                                        itemSchema = .string()
                                }
                                dict[param.name] = .array(items: itemSchema, description: param.description)
                            } else {
                                dict[param.name] = .array(items: .string(), description: param.description)
                            }
                        default:
                            dict[param.name] = .string(description: param.description)
                    }
                },
                required: metadata.parameters.filter { $0.defaultValue == nil }.map { $0.name },
                description: metadata.description ?? "No description available"
            )
            
            // Create the path item
            let pathItem = PathItem(
                post: Operation(
                    summary: metadata.name,
                    operationId: metadata.name,
                    description: metadata.description ?? "No description available",
                    requestBody: RequestBody(
                        required: true,
                        content: [
                            "application/json": Content(schema: inputSchema)
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
