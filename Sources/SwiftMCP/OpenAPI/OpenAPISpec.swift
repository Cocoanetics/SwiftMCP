import Foundation

/// Represents an OpenAPI 3.1.0 specification
struct OpenAPISpec: Codable {
    /// Basic information about the API
    struct Info: Codable {
        /// The title of the API
        let title: String
        /// The version of the API
        let version: String
        /// A description of the API
        let description: String
    }
    
    /// Server information
    struct Server: Codable {
        /// The server URL
        let url: String
        /// A description of the server
        let description: String
    }
    
    /// Request or response content
    struct Content: Codable {
        /// The schema defining the content structure
        let schema: JSONSchema
    }
    
    /// Request body specification
    struct RequestBody: Codable {
        /// Whether the request body is required
        let required: Bool
        /// The content types and their schemas
        let content: [String: Content]
    }
    
    /// Response specification
    struct Response: Codable {
        /// A description of the response
        let description: String
        /// The content types and their schemas, if any
        let content: [String: Content]?
    }
    
    /// Operation (e.g., POST) specification
    struct Operation: Codable {
        /// A brief summary of what the operation does
        let summary: String
        /// Unique identifier for the operation
        let operationId: String
        /// A detailed description of the operation
        let description: String
        /// The request body specification, if any
        let requestBody: RequestBody?
        /// The possible responses keyed by status code
        let responses: [String: Response]
		/// If the method requires extra confirmation
		let isConsequential: Bool?
        
        private enum CodingKeys: String, CodingKey {
            case summary
            case operationId
            case description
            case requestBody
            case responses
            case isConsequential = "x-openai-isConsequential"
        }
    }
    
    /// Path item specification
    struct PathItem: Codable {
        /// The POST operation specification, if any
        let post: Operation?
    }
    
    /// The OpenAPI specification version
    let openapi: String
    /// Basic information about the API
    let info: Info
    /// The servers where the API is available
    let servers: [Server]
    /// The available paths and their operations
    let paths: [String: PathItem]
    
    /**
     Creates an OpenAPI specification for an MCP server
     
     - Parameters:
       - server: The MCP server to create the spec for
       - scheme: The URL scheme to use (e.g., "http" or "https")
       - host: The host where the server is running
     */
    init(server: MCPServer, scheme: String, host: String) {
        self.openapi = "3.1.0"
        self.info = Info(
            title: "\(server.serverName)",
            version: server.serverVersion,
            description: server.serverDescription ?? "API for \(server.serverName) providing various tools."
        )
        
        self.servers = [
            Server(
                url: "\(scheme)://\(host)",
                description: "Production Server"
            )
        ]
        
        // Create paths from server tools
        let rootPath = server.serverName.asModelName
        var paths: [String: PathItem] = [:]
        
        for metadata in (server as? MCPToolProviding)?.mcpToolMetadata ?? [] {
            let pathKey = "/\(rootPath)/\(metadata.name)"
            
            // Create response schema based on return type
            let responseSchema: JSONSchema
            let responseDescription: String
            let voidDescription = "Empty string (void function)"
            
            if metadata.returnType == nil || metadata.returnType == Void.self {
                responseSchema = .string(description: voidDescription)
                responseDescription = metadata.returnTypeDescription ?? "A void function that performs an action"
            } else {
                // Convert Swift type to JSON Schema type
                let returnType = metadata.returnType!
                
                // Check if the type provides its own schema
                if let schemaType = returnType as? any SchemaRepresentable.Type {
                    responseSchema = schemaType.schema
                    responseDescription = metadata.returnTypeDescription ?? "A structured response"
                } else {
                    switch returnType {
                        case is Int.Type, is Double.Type:
                            responseSchema = .number(description: metadata.returnTypeDescription)
                        case is Bool.Type:
                            responseSchema = .boolean(description: metadata.returnTypeDescription)
                        case is Array<Any>.Type:
                            if let elementType = (returnType as? Array<Any>.Type)?.elementType {
                                let itemSchema: JSONSchema
                                switch elementType {
                                    case is Int.Type, is Double.Type:
                                        itemSchema = .number()
                                    case is Bool.Type:
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
                    // Use the parameter's JSONSchema directly
                    dict[param.name] = param.jsonSchema
                },
				required: metadata.parameters.filter { $0.isRequired }.map { $0.name },
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
					responses: responses, isConsequential: false
                )
            )
            
            paths[pathKey] = pathItem
        }
        
        self.paths = paths
    }
} 
