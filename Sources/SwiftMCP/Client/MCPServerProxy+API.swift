#if Client
import Foundation

extension MCPServerProxy {
    /// Lists all available tools from the server.
    public func listTools() async throws -> [MCPTool] {
        if cacheToolsList, let cachedTools = cachedTools {
            return cachedTools
        }

        let result: ToolsListResult = try await requestResult(
            method: "tools/list",
            as: ToolsListResult.self
        )
        let tools = result.tools

        if cacheToolsList {
            cachedTools = tools
        }

        return tools
    }

    /// Lists all static resources available from the server.
    public func listResources() async throws -> [SimpleResource] {
        let result: ResourcesListResult = try await requestResult(
            method: "resources/list",
            as: ResourcesListResult.self
        )
        return result.resources
    }

    /// Lists all resource templates available from the server.
    public func listResourceTemplates() async throws -> [SimpleResourceTemplate] {
        let result: ResourceTemplatesListResult = try await requestResult(
            method: "resources/templates/list",
            as: ResourceTemplatesListResult.self
        )
        return result.resourceTemplates
    }

    /// Reads a resource at the specified URI.
    public func readResource(uri: URL) async throws -> [GenericResourceContent] {
        let result: ResourceReadResult = try await requestResult(
            method: "resources/read",
            params: ["uri": .string(uri.absoluteString)],
            as: ResourceReadResult.self
        )
        return result.contents
    }

    /// Subscribes to update notifications for a resource URI.
    /// Requires a `resourceNotificationHandler` to be set and the server
    /// to advertise `resources.subscribe` capability.
    public func subscribeResource(uri: URL) async throws {
        _ = try await requestResult(
            method: "resources/subscribe",
            params: ["uri": .string(uri.absoluteString)]
        )
    }

    /// Unsubscribes from update notifications for a resource URI.
    public func unsubscribeResource(uri: URL) async throws {
        _ = try await requestResult(
            method: "resources/unsubscribe",
            params: ["uri": .string(uri.absoluteString)]
        )
    }

    /// Lists all prompts available from the server.
    public func listPrompts() async throws -> [Prompt] {
        let result: PromptsListResult = try await requestResult(
            method: "prompts/list",
            as: PromptsListResult.self
        )
        return result.prompts
    }

    /// Gets a prompt by name with optional arguments.
    public func getPrompt(
        name: String,
        arguments: JSONDictionary = [:]
    ) async throws -> PromptResult {
        try await requestResult(
            method: "prompts/get",
            params: [
                "name": .string(name),
                "arguments": .object(arguments)
            ],
            as: PromptResult.self
        )
    }

    /// Calls a tool by name on the connected MCP server with the provided arguments.
    public func callTool(
        _ name: String,
        arguments: JSONDictionary = [:],
        progressToken: JSONValue? = .string(UUID().uuidString)
    ) async throws -> String {
        let requestId = nextRequestID()
        var params: JSONDictionary = [
            "name": .string(name),
            "arguments": .object(arguments)
        ]

        // Merge base meta with progressToken
        var requestMeta = meta  // Start with base meta (e.g., accessToken)
        if let progressToken {
            requestMeta["progressToken"] = progressToken
        }

        if !requestMeta.isEmpty {
            params["_meta"] = .object(requestMeta)
        }

        let request = JSONRPCMessage.request(
            id: requestId,
            method: "tools/call",
            params: .object(params)
        )
        let responseMessage = try await send(request)

        let result = try extractToolCallResult(from: responseMessage)

        if result["isError"]?.boolValue == true {
            throw MCPServerProxyError.toolError(
                errorMessage(from: result) ?? "Tool call failed with an unspecified error."
            )
        }

        guard let contentArray = result["content"]?.arrayValue else {
            throw MCPServerProxyError.communicationError(
                "Invalid content format in tools/call response"
            )
        }

        if let text = extractTextPayload(from: contentArray) {
            return text
        }

        if let contentPayload = encodeContentPayload(from: contentArray) {
            return contentPayload
        }

        throw MCPServerProxyError.communicationError(
            "Failed to extract string content from tools/call response"
        )
    }

    private func extractToolCallResult(
        from responseMessage: JSONRPCMessage
    ) throws -> JSONDictionary {
        switch responseMessage {
        case .response(let responseData):
            guard let responseResult = responseData.result?.dictionaryValue else {
                throw MCPServerProxyError.communicationError(
                    "Invalid response type for tools/call, expected JSONRPCResponse"
                )
            }
            return responseResult
        case .errorResponse(let errorResponse):
            throw MCPServerProxyError.toolError(errorResponse.error.message)
        default:
            throw MCPServerProxyError.communicationError(
                "Invalid response type for tools/call, expected JSONRPCResponse"
            )
        }
    }

    /// Invalidates the cached list of tools.
    public func invalidateToolsCache() {
        cachedTools = nil
    }

    /// Sends a ping request to the server.
    public func ping() async throws {
        let requestId = nextRequestID()
        let request = JSONRPCMessage.request(id: requestId, method: "ping", params: nil)
        _ = try await send(request)
    }
}
#endif
