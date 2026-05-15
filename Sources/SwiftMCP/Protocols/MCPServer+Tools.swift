import Foundation

// MARK: - Tools (list / call)
public extension MCPServer {
    /**
     Creates a response listing all available tools.

     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC message containing the tools list
     */
    internal func createToolsListResponse(id: JSONRPCID) -> JSONRPCMessage {
        guard let toolProvider = self as? MCPToolProviding else {
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
        return JSONRPCMessage.errorResponse(
            id: id,
            error: .init(code: -32603, message: "Failed to encode tools list")
        )
    }

    /**
     Handles a tool execution request.

     - Parameter request: The JSON-RPC request containing the tool call details
     - Returns: A JSON-RPC message containing the tool execution result
     */
    internal func handleToolCall(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard let toolProvider = self as? MCPToolProviding else {
            return nil
        }

        guard let params = request.params,
              let toolName = params["name"]?.stringValue else {
            // Invalid request: missing tool name
            return nil
        }

        // Extract arguments from the request
        let arguments = params["arguments"]?.dictionaryValue ?? [:]

        let metadata = mcpToolMetadata(for: toolName)

        do {
            let result = try await toolProvider.callTool(toolName, arguments: arguments)
            let wrappedResult = try metadata?.wrapOutputIfNeeded(result) ?? result
            let expectsToolResult = metadata?.expectsToolResultReturn ?? false

            return try buildToolCallResponse(
                requestID: request.id,
                wrappedResult: wrappedResult,
                expectsToolResult: expectsToolResult
            )
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

    /// Builds the JSON-RPC response for a successful tool call by dispatching
    /// over the concrete content type of the wrapped result.
    private func buildToolCallResponse(
        requestID: JSONRPCID,
        wrappedResult: Encodable & Sendable,
        expectsToolResult: Bool
    ) throws -> JSONRPCMessage {
        var resultPayload: JSONDictionary = [
            "isError": false
        ]

        if let payload = try encodeSingleContent(wrappedResult) {
            resultPayload["content"] = payload
            return JSONRPCMessage.response(id: requestID, result: resultPayload)
        }

        if let payload = try encodeContentArray(wrappedResult, expectsToolResult: expectsToolResult) {
            resultPayload["content"] = payload
            return JSONRPCMessage.response(id: requestID, result: resultPayload)
        }

        if let payload = try encodeResourceContent(wrappedResult, expectsToolResult: expectsToolResult) {
            resultPayload["content"] = payload
            return JSONRPCMessage.response(id: requestID, result: resultPayload)
        }

        // Fallback: encode as JSON and wrap in a text content block.
        let (content, structured) = try encodeFallbackTextContent(wrappedResult)
        resultPayload["content"] = .array([.object(content)])
        if let structured {
            resultPayload["structuredContent"] = structured
        }
        return JSONRPCMessage.response(id: requestID, result: resultPayload)
    }

    /// Encodes a single MCP content value (text/image/audio/link/embedded) if applicable.
    private func encodeSingleContent(_ value: Any) throws -> JSONValue? {
        if let content = value as? MCPText {
            return try JSONValue(encoding: [content])
        }
        if let content = value as? MCPImage {
            return try JSONValue(encoding: [content])
        }
        if let content = value as? MCPAudio {
            return try JSONValue(encoding: [content])
        }
        if let content = value as? MCPResourceLink {
            return try JSONValue(encoding: [content])
        }
        if let content = value as? MCPEmbeddedResource {
            return try JSONValue(encoding: [content])
        }
        return nil
    }

    /// Encodes an array of MCP content values, returning `nil` when no homogeneous array matches.
    private func encodeContentArray(_ value: Any, expectsToolResult: Bool) throws -> JSONValue? {
        if let contents = value as? [MCPText], expectsToolResult || !contents.isEmpty {
            return try JSONValue(encoding: contents)
        }
        if let contents = value as? [MCPImage], expectsToolResult || !contents.isEmpty {
            return try JSONValue(encoding: contents)
        }
        if let contents = value as? [MCPAudio], expectsToolResult || !contents.isEmpty {
            return try JSONValue(encoding: contents)
        }
        if let contents = value as? [MCPResourceLink], expectsToolResult || !contents.isEmpty {
            return try JSONValue(encoding: contents)
        }
        if let contents = value as? [MCPEmbeddedResource], expectsToolResult || !contents.isEmpty {
            return try JSONValue(encoding: contents)
        }
        return nil
    }

    /// Encodes an `MCPResourceContent` (or array) by wrapping into embedded resources.
    private func encodeResourceContent(_ value: Any, expectsToolResult: Bool) throws -> JSONValue? {
        if let resource = value as? MCPResourceContent {
            return try JSONValue(encoding: [MCPEmbeddedResource(resource: resource)])
        }
        if let resources = value as? [MCPResourceContent], expectsToolResult || !resources.isEmpty {
            let contents = resources.map { MCPEmbeddedResource(resource: $0) }
            return try JSONValue(encoding: contents)
        }
        return nil
    }

    /// Encodes an arbitrary result as a single `text` content block, plus optional structured content.
    private func encodeFallbackTextContent(_ value: Encodable & Sendable) throws -> (JSONDictionary, JSONValue?) {
        let jsonValue = try JSONValue(encoding: value)
        let responseText: String
        if case .string(let value) = jsonValue {
            responseText = value
        } else if case .double(let value) = jsonValue, value == .infinity {
            responseText = "Infinity"
        } else if case .double(let value) = jsonValue, value == -.infinity {
            responseText = "-Infinity"
        } else if case .double(let value) = jsonValue, value.isNaN {
            responseText = "NaN"
        } else {
            let encoder = MCPJSONCoding.makeWireEncoder()
            let jsonData = try encoder.encode(jsonValue)
            responseText = String(data: jsonData, encoding: .utf8) ?? ""
        }

        let content: JSONDictionary = [
            "type": .string("text"),
            "text": .string(responseText)
        ]

        var structured: JSONValue?
        if case .object(let structuredObject) = jsonValue {
            structured = .object(structuredObject)
        }

        return (content, structured)
    }

    // MARK: - Internal Helpers

    /**
     Provides metadata for a function annotated with `@MCPTool`.

     - Parameter toolName: The name of the tool
     - Returns: The metadata for the tool

     This property uses runtime reflection to gather tool metadata from properties
     generated by the `@MCPTool` macro.
     */
    func mcpToolMetadata(for toolName: String) -> MCPToolMetadata? {
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
}

// MARK: - MCPToolMetadata helpers

extension MCPToolMetadata {
    /// True when the declared return type is an MCP content type (or array thereof),
    /// indicating that the caller expects a tool-result content envelope even when
    /// the runtime value happens to be an empty array.
    fileprivate var expectsToolResultReturn: Bool {
        guard let returnType = returnType else { return false }
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
    }
}
