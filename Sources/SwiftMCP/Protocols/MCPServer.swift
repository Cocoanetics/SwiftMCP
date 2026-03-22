import Foundation

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

            case "resources/subscribe":
                return await handleResourceSubscribe(requestData)

            case "resources/unsubscribe":
                return await handleResourceUnsubscribe(requestData)

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
           let capabilitiesValue = params["capabilities"],
           let clientCapabilities: ClientCapabilities = try? capabilitiesValue.decoded(ClientCapabilities.self) {

            if let session = Session.current {
                await session.setClientCapabilities(clientCapabilities)
            }
        }
        
        // Extract and store authentication metadata from _meta
        if let meta = RequestContext.current?.meta {
            if let accessToken = meta.accessToken {
                await Session.current?.setAccessToken(accessToken)
            }
        }
        
        var response = createInitializeResponse(id: request.id)

        // Conditionally advertise upload capability only on HTTP transports
        if let uploadHandler = self as? MCPFileUploadHandling,
           let transport = await Session.current?.transport,
           transport is HTTPSSETransport {
            if case .response(var responseData) = response,
               var result = responseData.result {
                var experimental = result["experimental"]?.dictionaryValue ?? [:]
                experimental["uploads"] = .object([
                    "endpoint": .string("/mcp/uploads"),
                    "maxSize": .integer(uploadHandler.maxUploadSize)
                ])
                result["experimental"] = .object(experimental)
                responseData.result = result
                response = .response(responseData)
            }
        }

        return response
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
            capabilities.resources = .init(subscribe: true, listChanged: true)
        }

        if self is MCPPromptProviding {
            capabilities.prompts = .init(listChanged: true)
        }

        if self is MCPLoggingProviding {
            capabilities.logging = .init(enabled: true)
        }



        // Advertise completion support
        capabilities.completions = .object([:])

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
            let resultDict = try JSONDictionary(encoding: result)
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
              let toolName = params["name"]?.stringValue else {
            // Invalid request: missing tool name
            return nil
        }

        // Extract arguments from the request
        var arguments = params["arguments"]?.dictionaryValue ?? [:]

        // Extract progress token for upload progress notifications
        let progressToken = params["_meta"]?.dictionaryValue?["progressToken"]

        // Resolve file:// uploads from _meta.uploads (local transports)
        let meta = params["_meta"]?.dictionaryValue
        let metaUploads = meta?["uploads"]?.dictionaryValue
        let uploadSessionID = meta?["uploadSessionID"]?.stringValue
        if let uploadSessionID, let resolved = try? Self.resolveFileUploads(in: arguments, metaUploads: metaUploads, uploadSessionID: uploadSessionID) {
            arguments = resolved
        }

        // Resolve remaining cid: placeholders by waiting for HTTP uploads
        if let pendingStore = PendingUploadResolver.current {
            do {
                if let resolved = try await Self.resolveCIDPlaceholders(
                    in: arguments,
                    sessionID: Session.current?.id ?? UUID(),
                    progressToken: progressToken,
                    pendingStore: pendingStore
                ) {
                    arguments = resolved
                }
            } catch {
                return JSONRPCMessage.errorResponse(
                    id: request.id,
                    error: .init(code: -32603, message: "Upload resolution failed: \(error.localizedDescription)")
                )
            }
        }

        let metadata = mcpToolMetadata(for: toolName)

        // Call the appropriate wrapper method based on the tool name
        do {
            let result = try await toolProvider.callTool(toolName, arguments: arguments)
            let wrappedResult = try metadata?.wrapOutputIfNeeded(result) ?? result

            var content: JSONDictionary
            var resultPayload: JSONDictionary = [
                "isError": false
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
                resultPayload["content"] = try JSONValue(encoding: [content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let content = wrappedResult as? MCPImage {
                resultPayload["content"] = try JSONValue(encoding: [content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let content = wrappedResult as? MCPAudio {
                resultPayload["content"] = try JSONValue(encoding: [content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let content = wrappedResult as? MCPResourceLink {
                resultPayload["content"] = try JSONValue(encoding: [content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let content = wrappedResult as? MCPEmbeddedResource {
                resultPayload["content"] = try JSONValue(encoding: [content])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPText],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = try JSONValue(encoding: contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPImage],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = try JSONValue(encoding: contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPAudio],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = try JSONValue(encoding: contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPResourceLink],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = try JSONValue(encoding: contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let contents = wrappedResult as? [MCPEmbeddedResource],
                      (expectsToolResult || !contents.isEmpty) {
                resultPayload["content"] = try JSONValue(encoding: contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let resource = wrappedResult as? MCPResourceContent {
                resultPayload["content"] = try JSONValue(encoding: [MCPEmbeddedResource(resource: resource)])
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else if let resources = wrappedResult as? [MCPResourceContent],
                      (expectsToolResult || !resources.isEmpty) {
                let contents = resources.map { MCPEmbeddedResource(resource: $0) }
                resultPayload["content"] = try JSONValue(encoding: contents)
                return JSONRPCMessage.response(id: request.id, result: resultPayload)
            } else {
                let jsonValue = try JSONValue(encoding: wrappedResult)
                let encoder = MCPJSONCoding.makeWireEncoder()
                let jsonData = try encoder.encode(jsonValue)
                let responseText = String(data: jsonData, encoding: .utf8) ?? ""

                content = [
                    "type": .string("text"),
                    "text": .string(responseText.removingQuotes)
                ]

                if case .object(let structuredObject) = jsonValue {
                    resultPayload["structuredContent"] = .object(structuredObject)
                }
            }

            resultPayload["content"] = .array([.object(content)])

            return JSONRPCMessage.response(id: request.id, result: resultPayload)

        } catch {
            return JSONRPCMessage.response(
                id: request.id,
                result: [
                    "content": .array([.object([
                        "type": .string("text"),
                        "text": .string(error.localizedDescription)
                    ])]),
                    "isError": true
                ]
            )
        }
    }


    /// Handles a prompt get request
    private func handlePromptGet(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard let promptProvider = self as? MCPPromptProviding else {
            return nil
        }

        guard let params = request.params,
              let name = params["name"]?.stringValue else {
            return JSONRPCMessage.errorResponse(id: request.id, error: .init(code: -32602, message: "Missing prompt name"))
        }

        let arguments = params["arguments"]?.dictionaryValue ?? [:]

        do {
            let messages = try await promptProvider.callPrompt(name, arguments: arguments)
            return JSONRPCMessage.response(
                id: request.id,
                result: [
                    "description": .string(name),
                    "messages": try JSONValue(encoding: messages)
                ]
            )
        } catch {
            return JSONRPCMessage.errorResponse(id: request.id, error: .init(code: -32000, message: error.localizedDescription))
        }
    }

    /// Handles a completion request for argument autocompletion.
    private func handleCompletion(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {

        guard let params = request.params,
              let refDict = params["ref"]?.dictionaryValue,
              let argDict = params["argument"]?.dictionaryValue,
              let argName = argDict["name"]?.stringValue else {
            return JSONRPCMessage.response(id: request.id, result: ["completion": .object(["values": .array([])])])
        }

        let prefix = argDict["value"]?.stringValue ?? ""

        if let refType = refDict["type"]?.stringValue,
           refType == "ref/resource",
           let uri = refDict["uri"]?.stringValue,
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

            let result: JSONDictionary = [
                "completion": .object([
                    "values": try! JSONValue(encoding: comp.values),
                    "total": .integer(comp.total ?? comp.values.count),
                    "hasMore": .bool(comp.hasMore ?? false)
                ])
            ]
            return JSONRPCMessage.response(id: request.id, result: result)
        }

        if let refType = refDict["type"]?.stringValue,
           refType == "ref/prompt",
           let name = refDict["name"]?.stringValue,
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

            let result: JSONDictionary = [
                "completion": .object([
                    "values": try! JSONValue(encoding: comp.values),
                    "total": .integer(comp.total ?? comp.values.count),
                    "hasMore": .bool(comp.hasMore ?? false)
                ])
            ]
            return JSONRPCMessage.response(id: request.id, result: result)
        }

        // Fallback empty response
        return JSONRPCMessage.response(id: request.id, result: ["completion": .object(["values": .array([])])])
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

        if let tools = try? JSONValue(encoding: toolProvider.mcpToolMetadata.convertedToTools()) {
            return JSONRPCMessage.response(id: id, result: ["tools": tools])
        }
        return JSONRPCMessage.errorResponse(id: id, error: .init(code: -32603, message: "Failed to encode tools list"))
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
        if let promptsValue = try? JSONValue(encoding: prompts) {
            return JSONRPCMessage.response(id: id, result: ["prompts": promptsValue])
        }
        return JSONRPCMessage.errorResponse(id: id, error: .init(code: -32603, message: "Failed to encode prompts list"))
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

        if let resourcesValue = try? JSONValue(encoding: resources.map { resource in
            [
                "uri": resource.uri.absoluteString,
                "name": resource.name,
                "description": resource.description,
                "mimeType": resource.mimeType
            ]
        }) {
            return JSONRPCMessage.response(id: id, result: ["resources": resourcesValue])
        }
        return JSONRPCMessage.errorResponse(id: id, error: .init(code: -32603, message: "Failed to encode resources list"))
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
        guard let uriString = request.params?["uri"]?.stringValue,
				  let uri = URL(string: uriString) else {
            return JSONRPCMessage.errorResponse(id: id, error: .init(code: -32602, message: "Invalid or missing URI parameter"))
        }

        do {
            // Try to get the resource content
            let resourceContentArray = try await resourceProvider.getResource(uri: uri)

            if !resourceContentArray.isEmpty
				{
                let contents = try resourceContentArray.map { try JSONValue(encoding: $0) }
                return JSONRPCMessage.response(id: id, result: ["contents": .array(contents)])
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

        if let templatesValue = try? JSONValue(encoding: templates.map { template in
            [
                "uriTemplate": template.uriTemplate,
                "name": template.name,
                "description": template.description,
                "mimeType": template.mimeType ?? "text/plain"
            ]
        }) {
            return JSONRPCMessage.response(id: id, result: ["resourceTemplates": templatesValue])
        }
        return JSONRPCMessage.errorResponse(id: id, error: .init(code: -32603, message: "Failed to encode resource templates list"))
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
              let levelString = params["level"]?.stringValue else {
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

    // MARK: - CID Upload Resolution

    /// The base directory for session-scoped file uploads.
    static var uploadBaseDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("mcp-uploads", isDirectory: true)
    }

    /// Resolves `cid:` placeholders that have a matching `file://` path in `_meta.uploads`.
    /// Only accepts files inside the session-scoped upload directory to prevent path traversal.
    /// The file is memory-mapped and base64-encoded into the arguments. Temp files are deleted after reading.
    /// Returns the updated arguments, or nil if no file-based CIDs were resolved.
    private static func resolveFileUploads(
        in arguments: JSONDictionary,
        metaUploads: JSONDictionary?,
        uploadSessionID: String
    ) throws -> JSONDictionary? {
        guard let metaUploads else { return nil }

        // Only accept files from the session-scoped upload directory
        let allowedDir = uploadBaseDirectory
            .appendingPathComponent(uploadSessionID, isDirectory: true)
            .path

        var resolved = arguments
        var didResolve = false

        for (key, value) in arguments {
            guard let str = value.stringValue, str.hasPrefix("cid:") else { continue }
            let cid = String(str.dropFirst(4))

            guard let filePath = metaUploads[cid]?.stringValue,
                  filePath.hasPrefix("file://"),
                  let fileURL = URL(string: filePath) else { continue }

            // Reject paths outside the session upload directory
            guard fileURL.path.hasPrefix(allowedDir) else { continue }

            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            resolved[key] = .string(data.base64EncodedString())
            try? FileManager.default.removeItem(at: fileURL)
            didResolve = true
        }

        return didResolve ? resolved : nil
    }

    /// Scans tool call arguments for `cid:` placeholders and waits for corresponding uploads.
    /// Returns the arguments with CIDs replaced by base64 data, or nil if no CIDs found.
    private static func resolveCIDPlaceholders(
        in arguments: JSONDictionary,
        sessionID: UUID,
        progressToken: JSONValue?,
        pendingStore: PendingUploadStore
    ) async throws -> JSONDictionary? {
        var cidEntries: [(key: String, cid: String)] = []
        for (key, value) in arguments {
            if let str = value.stringValue, str.hasPrefix("cid:") {
                cidEntries.append((key: key, cid: String(str.dropFirst(4))))
            }
        }

        guard !cidEntries.isEmpty else { return nil }

        var resolved = arguments

        for (index, entry) in cidEntries.enumerated() {
            if let token = progressToken, let session = Session.current {
                let total = Double(cidEntries.count)
                let message = cidEntries.count == 1
                    ? "Waiting for file upload..."
                    : "Waiting for file upload \(index + 1) of \(cidEntries.count)..."
                await session.sendProgressNotification(
                    progressToken: token,
                    progress: Double(index),
                    total: total,
                    message: message
                )
            }

            let fileURL = try await pendingStore.waitForUpload(
                cid: entry.cid,
                progressToken: progressToken,
                sessionID: sessionID
            )

            let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
            resolved[entry.key] = .string(data.base64EncodedString())
            try? FileManager.default.removeItem(at: fileURL)
        }

        if let token = progressToken, let session = Session.current {
            await session.sendProgressNotification(
                progressToken: token,
                progress: Double(cidEntries.count),
                total: Double(cidEntries.count),
                message: "All uploads received"
            )
        }

        return resolved
    }

    // MARK: - Resource Subscriptions

    private func handleResourceSubscribe(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard let session = Session.current else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32603, message: "No session context for resources/subscribe")
            )
        }

        guard let params = request.params,
              let uri = params["uri"]?.stringValue else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid parameters: 'uri' parameter is required")
            )
        }

        await session.subscribeResource(uri: uri)
        return JSONRPCMessage.response(id: request.id, result: [:])
    }

    private func handleResourceUnsubscribe(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard let session = Session.current else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32603, message: "No session context for resources/unsubscribe")
            )
        }

        guard let params = request.params,
              let uri = params["uri"]?.stringValue else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid parameters: 'uri' parameter is required")
            )
        }

        await session.unsubscribeResource(uri: uri)
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
        let mirror = Mirror(reflecting: self)

        // Direct lookup (tool name == function name)
        if let child = mirror.children.first(where: { $0.label == metadataKey }),
           let metadata = child.value as? MCPToolMetadata,
           metadata.name == toolName {
            return metadata
        }

        // Fallback: search all metadata by name property
        // (handles custom name overrides where tool name ≠ function name)
        for child in mirror.children {
            guard let label = child.label, label.hasPrefix("__mcpMetadata_"),
                  let metadata = child.value as? MCPToolMetadata,
                  metadata.name == toolName else { continue }
            return metadata
        }

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
