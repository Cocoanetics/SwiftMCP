import Foundation

/// Represents an OpenAPI 3.1.0 specification
public struct OpenAPISpec: Codable {
    /// Basic information about the API
    public struct Info: Codable {
        /// The title of the API
        public let title: String
        /// The version of the API
        public let version: String
        /// A description of the API
        public let description: String
    }
    
    /// Server information
    public struct Server: Codable {
        /// The server URL
        public let url: String
        /// A description of the server
        public let description: String
    }
    
    /// Request or response content
    public struct Content: Codable {
        /// The schema defining the content structure
        public let schema: JSONSchema
    }
    
    /// Request body specification
    public struct RequestBody: Codable {
        /// Whether the request body is required
        public let required: Bool
        /// The content types and their schemas
        public let content: [String: Content]
    }
    
    /// Response specification
    public struct Response: Codable {
        /// A description of the response
        public let description: String
        /// The content types and their schemas, if any
        public let content: [String: Content]?
    }
    
    /// Operation (e.g., POST) specification
    public struct Operation: Codable {
        /// A brief summary of what the operation does
        public let summary: String
        /// Unique identifier for the operation
        public let operationId: String
        /// A detailed description of the operation
        public let description: String
        /// The request body specification, if any
        public let requestBody: RequestBody?
        /// The possible responses keyed by status code
        public let responses: [String: Response]
    }
    
    /// Path item specification
    public struct PathItem: Codable {
        /// The POST operation specification, if any
        public let post: Operation?
    }
    
    /// The OpenAPI specification version
    public let openapi: String
    /// Basic information about the API
    public let info: Info
    /// The servers where the API is available
    public let servers: [Server]
    /// The available paths and their operations
    public let paths: [String: PathItem]
    
    /**
     Creates an OpenAPI specification for an MCP server
     
     - Parameters:
       - server: The MCP server to create the spec for
       - scheme: The URL scheme to use (e.g., "http" or "https")
       - host: The host where the server is running
     */
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
