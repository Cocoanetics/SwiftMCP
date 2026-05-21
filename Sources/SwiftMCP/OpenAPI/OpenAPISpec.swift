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
        let isConsequential: Bool

        // swiftlint:disable:next nesting
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
    init(server: MCPServer, scheme: String, host: String) async {
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

        // Combine MCPTool, MCPResource, and MCPPrompt functions as tools
        let allToolMetadata = await Self.collectToolMetadata(for: server)

        // Generate OpenAPI paths for all tools
        let rootPath = server.serverName.asModelName
        var paths: [String: PathItem] = [:]
        for metadata in allToolMetadata {
            let pathKey = "/\(rootPath)/\(metadata.name)"
            paths[pathKey] = Self.makePathItem(for: metadata)
        }

        self.paths = paths
    }

    /// Collects the union of MCPTool / MCPResource / MCPPrompt metadata exposed by `server`,
    /// rewriting resource/prompt metadata into tool metadata so they can share a single output path.
    ///
    /// `async` because `mcpToolMetadata` / `mcpPromptMetadata` may be actor-isolated
    /// when the host is an `actor`; the `await` hops onto the executor in that case
    /// and is a no-op for class hosts.
    private static func collectToolMetadata(for server: MCPServer) async -> [MCPToolMetadata] {
        var allToolMetadata: [MCPToolMetadata] = []

        // Add MCPTool functions
        if let toolProvider = server as? MCPToolProviding {
            allToolMetadata.append(contentsOf: await toolProvider.mcpToolMetadata)
        }

        // Add MCPResource functions converted to tools
        if let resourceProvider = server as? MCPResourceProviding {
            let resourceMetadata = await resourceProvider.mcpResourceMetadata
            let resourceAsTools = resourceMetadata.map { resourceMeta in
                MCPToolMetadata(
                    name: resourceMeta.functionMetadata.name,
                    description: resourceMeta.description,
                    parameters: resourceMeta.parameters,
                    returnType: OpenAIFileResponse.self,
                    returnTypeDescription: resourceMeta.returnTypeDescription,
                    isAsync: resourceMeta.isAsync,
                    isThrowing: resourceMeta.isThrowing,
                    isConsequential: false // Resources are generally not consequential
                )
            }
            allToolMetadata.append(contentsOf: resourceAsTools)
        }

        // Add MCPPrompt functions converted to tools
        if let promptProvider = server as? MCPPromptProviding {
            let promptAsTools = await promptProvider.mcpPromptMetadata.map { promptMeta in
                MCPToolMetadata(
                    name: promptMeta.name,
                    description: promptMeta.description,
                    parameters: promptMeta.parameters,
                    returnType: [PromptMessage].self,
                    returnTypeDescription: "Array of PromptMessage objects",
                    isAsync: promptMeta.isAsync,
                    isThrowing: promptMeta.isThrowing,
                    isConsequential: false
                )
            }
            allToolMetadata.append(contentsOf: promptAsTools)
        }

        return allToolMetadata
    }

    /// Builds a `PathItem` representing one tool, with its input schema (request body), success
    /// response and (if throwing) error response.
    private static func makePathItem(for metadata: MCPToolMetadata) -> PathItem {
        let returnInfo = metadata.returnSchemaInfo
        let responseSchema = returnInfo.schema
        let responseDescription = returnInfo.description

        var responses: [String: Response] = [
            "200": Response(
                description: responseDescription,
                content: [
                    "application/json": Content(schema: responseSchema.withoutRequired)
                ]
            )
        ]

        // Add error response if the function can throw
        if metadata.isThrowing {
            responses["400"] = Response(
                description: "The function threw an error",
                content: [
                    "application/json": Content(schema: errorResponseSchema().withoutRequired)
                ]
            )
        }

        let inputSchema = makeInputSchema(for: metadata)

        return PathItem(
            post: Operation(
                summary: metadata.name,
                operationId: metadata.name,
                description: metadata.description ?? "No description available",
                requestBody: metadata.parameters.isEmpty ? nil : RequestBody(
                    required: true,
                    content: [
                        "application/json": Content(schema: inputSchema)
                    ]
                ),
                responses: responses,
                isConsequential: metadata.computedIsConsequential
            )
        )
    }

    /// Constructs the canonical `{"error": {"code": Int, "message": String}}` schema used for
    /// error responses across all tool paths.
    private static func errorResponseSchema() -> JSONSchema {
        JSONSchema.object(JSONSchema.Object(
            properties: [
                "error": .object(JSONSchema.Object(
                    properties: [
                        "code": .number(title: nil, description: nil, minimum: nil, maximum: nil),
                        "message": .string(title: nil, description: nil)
                    ],
                    required: ["code", "message"]
                ))
            ],
            required: ["error"],
            description: "Error response containing the error code and message"
        ))
    }

    /// Builds the request-body schema for `metadata`, mapping each parameter to its `JSONSchema`
    /// and marking required parameters explicitly.
    private static func makeInputSchema(for metadata: MCPToolMetadata) -> JSONSchema {
        JSONSchema.object(JSONSchema.Object(
            properties: metadata.parameters.reduce(into: [:]) { dict, param in
                // Use the parameter's JSONSchema directly
                dict[param.name] = param.schema
            },
            required: metadata.parameters.filter { $0.isRequired }.map { $0.name },
            description: metadata.description ?? "No description available"
        ))
    }
}
