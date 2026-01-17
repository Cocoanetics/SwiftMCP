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
     Handles a JSON-RPC message and generates an appropriate response.
     
     - Parameter message: The JSON-RPC message to handle
     - Returns: A response message if one should be sent, nil otherwise
     */
    func handleMessage(_ message: JSONRPCMessage) async -> JSONRPCMessage?

    /// Called when the roots list has changed. Default implementation does nothing.
    func handleRootsListChanged() async
}

// MARK: - Default Implementations
public extension MCPServer {
/**
     Default implementation for handling JSON-RPC messages.
     
     This implementation supports the following message types:
     - request: Handles various JSON-RPC requests
     - notification: Handles notifications (no response expected)
     - response: Handles responses from other parties
     - errorResponse: Handles error responses
     
     For requests, it supports these methods:
     - initialize: Server initialization
     - notifications/initialized: Client initialization notification
     - ping: Server health check
     - tools/list: List available tools
     - resources/list: List available resources
     - resources/templates/list: List available resource templates
     - resources/read: Read a specific resource
     - tools/call: Execute a tool
     
     - Parameter message: The JSON-RPC message to handle
     - Returns: A response message if one should be sent, nil otherwise
     */
    func handleMessage(_ message: JSONRPCMessage) async -> JSONRPCMessage? {
        let context = RequestContext(message: message)
        return await context.work { _ in
            // First switch on message type
            switch message {
                case .request(let requestData):
                    return await handleRequest(requestData)

                case .notification(let notificationData):
                    return await handleNotification(notificationData)

                case .response(let responseData):
                    return await handleResponse(responseData)

                case .errorResponse(let errorResponseData):
                    return await handleErrorResponse(errorResponseData)
            }
        }
    }

/**
     Handles JSON-RPC requests that expect responses.
     
     - Parameter requestData: The request data
     - Returns: A response message if one should be sent, nil otherwise
     */
    private func handleRequest(_ requestData: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        // Prepare the response based on the method
        switch requestData.method {
            case "initialize":
                return await handleInitializeRequest(requestData)

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

            case "prompts/list":
                return createPromptsListResponse(id: requestData.id)

            case "prompts/get":
                return await handlePromptGet(requestData)

            case "completion/complete":
                return await handleCompletion(requestData)

            case "tools/call":
                return await handleToolCall(requestData)

            case "logging/setLevel":
                return await handleLoggingSetLevel(requestData)



            default:
                // Respond with JSON-RPC error for method not found
                return JSONRPCMessage.errorResponse(id: requestData.id, error: .init(code: -32601, message: "Method not found"))
        }
    }

/**
     Handles JSON-RPC notifications (no response expected).
     
     - Parameter notificationData: The notification data
     - Returns: Always returns nil since notifications don't expect responses
     */
    private func handleNotification(_ notificationData: JSONRPCMessage.JSONRPCNotificationData) async -> JSONRPCMessage? {
        switch notificationData.method {
            case "notifications/initialized":
                // Client has completed initialization
                return nil

            case "notifications/cancelled":
                // Client has cancelled a request
                return nil

            case "notifications/roots/list_changed":
                // Client's root list has changed
                await self.handleRootsListChanged()
                return nil

            default:
                // Unknown notification - log it but don't respond
                return nil
        }
    }
    
    /// Handles the roots list changed notification by retrieving the updated roots list.
    func handleRootsListChanged() async {}

/**
     Handles JSON-RPC responses from other parties.
     
     - Parameter responseData: The response data
     - Returns: Always returns nil since we don't currently respond to responses
     */
    private func handleResponse(_ responseData: JSONRPCMessage.JSONRPCResponseData) async -> JSONRPCMessage? {
        // Route the response to the current session for request/response matching
        let response = JSONRPCMessage.response(responseData)
        if let session = Session.current {
            await session.handleResponse(response)
        }
        return nil
    }

/**
     Handles JSON-RPC error responses from other parties.
     
     - Parameter errorResponseData: The error response data
     - Returns: Always returns nil since we don't currently respond to error responses
     */
    private func handleErrorResponse(_ errorResponseData: JSONRPCMessage.JSONRPCErrorResponseData) async -> JSONRPCMessage? {
        // Route the error response to the current session for request/response matching
        let response = JSONRPCMessage.errorResponse(errorResponseData)
        if let session = Session.current {
            await session.handleResponse(response)
        }
        return nil
    }

/**
     Handles an initialization request from the client.
     
     This processes the client capabilities and stores them in the current session,
     then creates and returns an initialization response.
     
     - Parameter request: The initialization request data
     - Returns: A JSON-RPC message containing the initialization response
     */
    private func handleInitializeRequest(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        // Extract and store client capabilities if provided
        if let params = request.params,
           let capabilitiesDict = params["capabilities"]?.value as? [String: Any] {
            
            do {
                let capabilitiesData = try JSONSerialization.data(withJSONObject: capabilitiesDict)
                let clientCapabilities = try JSONDecoder().decode(ClientCapabilities.self, from: capabilitiesData)
                
                // Store client capabilities in current session
                if let session = Session.current {
                    await session.setClientCapabilities(clientCapabilities)
                }
            } catch {
                // If parsing fails, continue without client capabilities
                // This is non-fatal as not all clients may send capabilities
            }
        }
        
        return createInitializeResponse(id: request.id)
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
    func createInitializeResponse(id: JSONRPCID) -> JSONRPCMessage {
        var capabilities = ServerCapabilities()

        if self is MCPToolProviding {
            capabilities.tools = .init(listChanged: true)
        }

        if self is MCPResourceProviding {
            capabilities.resources = .init(listChanged: true)
        }

        if self is MCPPromptProviding {
            capabilities.prompts = .init(listChanged: true)
        }

        if self is MCPLoggingProviding {
            capabilities.logging = .init(enabled: true)
        }



        // Advertise completion support
        capabilities.completions = AnyCodable([:])

        let serverInfo = InitializeResult.ServerInfo(
            name: serverName,
            version: serverVersion,
            description: serverDescription
        )

        let result = InitializeResult(
            protocolVersion: "2025-06-18",
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

        let metadata = mcpToolMetadata(for: toolName)

        // Call the appropriate wrapper method based on the tool name
        do {
            let result = try await toolProvider.callTool(toolName, arguments: arguments)
            let wrappedResult = metadata?.wrapOutputIfNeeded(result) ?? result

            var content: [String: Any]
            var resultPayload: [String: AnyCodable] = [
                "isError": AnyCodable(false)
            ]

            let expectsToolResult: Bool = {
                guard let returnType = metadata?.returnType else {
                    return false
                }
                return returnType is MCPText.Type
                    || returnType is MCPImage.Type
                    || returnType is MCPAudio.Type
                    || returnType is MCPResourceLink.Type
                    || returnType is MCPEmbeddedResource.Type
                    || returnType is [MCPText].Type
                    || returnType is [MCPImage].Type
                    || returnType is [MCPAudio].Type
                    || returnType is [MCPResourceLink].Type
                    || returnType is [MCPEmbeddedResource].Type
                    || returnType is any MCPResourceContent.Type
                    || returnType is [any MCPResourceContent].Type
            }()

            if let content = wrappedResult as? MCPText {
                resultPayload["content"] = AnyCodable([content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let content = wrappedResult as? MCPImage {
                resultPayload["content"] = AnyCodable([content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let content = wrappedResult as? MCPAudio {
                resultPayload["content"] = AnyCodable([content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let content = wrappedResult as? MCPResourceLink {
                resultPayload["content"] = AnyCodable([content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let content = wrappedResult as? MCPEmbeddedResource {
                resultPayload["content"] = AnyCodable([content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPText],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = AnyCodable(contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPImage],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = AnyCodable(contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPAudio],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = AnyCodable(contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPResourceLink],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = AnyCodable(contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPEmbeddedResource],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = AnyCodable(contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let resource = wrappedResult as? MCPResourceContent {
                resultPayload["content"] = AnyCodable([MCPEmbeddedResource(resource: resource)])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let resources = wrappedResult as? [MCPResourceContent],
                      (expectsToolResult || !resources.isEmpty) {
                let contents = resources.map { MCPEmbeddedResource(resource: $0) }
                resultPayload["content"] = AnyCodable(contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else {
                let encoder = JSONEncoder()

                // Create ISO8601 formatter with timezone
                encoder.dateEncodingStrategy = .iso8601WithTimeZone
                encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "Infinity", negativeInfinity: "-Infinity", nan: "NaN")
                encoder.outputFormatting = [.sortedKeys]

                let jsonData = try encoder.encode(wrappedResult)
                let responseText = String(data: jsonData, encoding: .utf8) ?? ""

                content = [
                    "type": "text",
                    "text": responseText.removingQuotes
                ]

                if let structuredObject = try? DictionaryEncoder().encode(wrappedResult) {
                    resultPayload["structuredContent"] = AnyCodable(structuredObject)
                }
            }

            resultPayload["content"] = AnyCodable([content])

            return JSONRPCMessage.response(id: request.id, result: resultPayload)

        } catch {
            return JSONRPCMessage.response(id: request.id, result: [
                "content": [
                    ["type": "text", "text": error.localizedDescription]
                ],
                "isError": true
            ])
        }
    }


    /// Handles a prompt get request
    private func handlePromptGet(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard let promptProvider = self as? MCPPromptProviding else {
            return nil
        }

        guard let params = request.params,
              let name = params["name"]?.value as? String else {
            return JSONRPCMessage.errorResponse(id: request.id, error: .init(code: -32602, message: "Missing prompt name"))
        }

        let arguments = (params["arguments"]?.value as? [String: Sendable]) ?? [:]

        do {
            let messages = try await promptProvider.callPrompt(name, arguments: arguments)
            return JSONRPCMessage.response(id: request.id, result: ["description": AnyCodable(name), "messages": AnyCodable(messages)])
        } catch {
            return JSONRPCMessage.errorResponse(id: request.id, error: .init(code: -32000, message: error.localizedDescription))
        }
    }

    /// Handles a completion request for argument autocompletion.
    private func handleCompletion(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {

        guard let params = request.params,
              let refDict = params["ref"]?.value as? [String: Any],
              let argDict = params["argument"]?.value as? [String: Any],
              let argName = argDict["name"] as? String else {
            return JSONRPCMessage.response(id: request.id, result: ["completion": ["values": []]].mapValues { AnyCodable($0) })
        }

        let prefix = (argDict["value"] as? String) ?? ""

        if let refType = refDict["type"] as? String,
           refType == "ref/resource",
           let uri = refDict["uri"] as? String,
           let resourceProvider = self as? MCPResourceProviding,
           let metadata = resourceProvider.mcpResourceMetadata.first(where: { $0.uriTemplates.contains(uri) }),
           let parameter = metadata.parameters.first(where: { $0.name == argName }) {

            let comp: CompleteResult.Completion
            if let completionProvider = self as? MCPCompletionProviding {
                comp = await completionProvider.completion(for: parameter, in: .resource(metadata), prefix: prefix)
            } else {
                let completions = parameter.defaultCompletions.sortedByBestCompletion(prefix: prefix)
                comp = CompleteResult.Completion(values: completions, total: completions.count, hasMore: false)
            }

            let result: [String: Any] = [
                "completion": [
                    "values": comp.values,
                    "total": comp.total ?? comp.values.count,
                    "hasMore": comp.hasMore ?? false
                ]
            ]
            return JSONRPCMessage.response(id: request.id, result: result.mapValues { AnyCodable($0) })
        }

        if let refType = refDict["type"] as? String,
           refType == "ref/prompt",
           let name = refDict["name"] as? String,
           let promptProvider = self as? MCPPromptProviding,
           let metadata = promptProvider.mcpPromptMetadata.first(where: { $0.name == name }),
           let parameter = metadata.parameters.first(where: { $0.name == argName }) {

            let comp: CompleteResult.Completion
            if let completionProvider = self as? MCPCompletionProviding {
                comp = await completionProvider.completion(for: parameter, in: .prompt(metadata), prefix: prefix)
            } else {
                let completions = parameter.defaultCompletions.sortedByBestCompletion(prefix: prefix)
                comp = CompleteResult.Completion(values: completions, total: completions.count, hasMore: false)
            }

            let result: [String: Any] = [
                "completion": [
                    "values": comp.values,
                    "total": comp.total ?? comp.values.count,
                    "hasMore": comp.hasMore ?? false
                ]
            ]
            return JSONRPCMessage.response(id: request.id, result: result.mapValues { AnyCodable($0) })
        }

        // Fallback empty response
        return JSONRPCMessage.response(id: request.id, result: ["completion": ["values": []]].mapValues { AnyCodable($0) })
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
    private func createToolsListResponse(id: JSONRPCID) -> JSONRPCMessage {

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

    /// Creates a response listing all available prompts.
    private func createPromptsListResponse(id: JSONRPCID) -> JSONRPCMessage {
        guard let promptProvider = self as? MCPPromptProviding else {
            return JSONRPCMessage.response(id: id, result: [
                "content": [["type": "text", "text": "Server does not provide any prompts"]],
                "isError": true
            ])
        }

        let prompts = promptProvider.mcpPromptMetadata.convertedToPrompts()
        return JSONRPCMessage.response(id: id, result: ["prompts": AnyCodable(prompts)])
    }

/**
	 Creates a response listing all available resources.
	 
	 - Parameter id: The request ID to include in the response
	 - Returns: A JSON-RPC message containing the resources list
	 */
    func createResourcesListResponse(id: JSONRPCID) async -> JSONRPCMessage {

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
    func createResourcesReadResponse(id: JSONRPCID, request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage {

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
    func createResourceTemplatesListResponse(id: JSONRPCID) async -> JSONRPCMessage {

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
					"mimeType": template.mimeType ?? "text/plain"
				]
        })
		])
    }

/**
     Creates a ping response with empty result.
     
     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC response for ping
     */
    func createPingResponse(id: JSONRPCID) -> JSONRPCMessage {
        return JSONRPCMessage.response(id: id, result: [:])
    }

    /**
     Handles a logging level configuration request.
     
     - Parameter request: The JSON-RPC request containing the logging level details
     - Returns: A JSON-RPC message containing the result
     */
    private func handleLoggingSetLevel(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard let session = Session.current else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32603, message: "No session context for logging/setLevel")
            )
        }

        guard let params = request.params,
              let levelString = params["level"]?.value as? String else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid parameters: 'level' parameter is required")
            )
        }

        guard let level = LogLevel(string: levelString) else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid log level: '\(levelString)'. Valid levels are: \(LogLevel.allCases.map(\.rawValue).joined(separator: ", "))")
            )
        }

        // Set the minimum log level for this session
        await session.setMinimumLogLevel(level)

        // Return empty result for success
        return JSONRPCMessage.response(id: request.id, result: [:])
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
            #if canImport(AppIntents)
            if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
                if let providerType = Self.self as? MCPAppShortcutsProvider.Type {
                    let shortcutMetadata = MCPAppIntentTools.toolMetadata(for: providerType)
                    return shortcutMetadata.first(where: { $0.name == toolName })
                }
            }
            #endif
            return nil
        }

        return metadata
    }

    /// Retrieves metadata for a prompt function by name
    func mcpPromptMetadata(for name: String) -> MCPPromptMetadata? {
        let key = "__mcpPromptMetadata_\(name)"
        let mirror = Mirror(reflecting: self)
        guard let child = mirror.children.first(where: { $0.label == key }),
              let metadata = child.value as? MCPPromptMetadata else {
            return nil
        }
        return metadata
    }
}
