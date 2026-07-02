import Foundation

// MARK: - Tools (list / call)
public extension MCPServer {
    /**
     Creates a response listing all available tools.

     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC message containing the tools list
     */
    internal func createToolsListResponse(id: JSONRPCID) async -> JSONRPCMessage {
        guard let toolProvider = self as? MCPToolProviding else {
            return JSONRPCMessage.response(id: id, result: [
                "content": [
                    ["type": "text", "text": "Server does not provide any tools"]
                ],
                "isError": true
            ])
        }

        // `outputSchema` is a 2025-06-18 feature; omit it for older clients.
        let includeOutputSchema = await RequestContext.current?.supports(.structuredToolOutput) ?? true
        let toolMetadata = await toolProvider.mcpToolMetadata
        let tools = toolMetadata.convertedToTools(includeOutputSchema: includeOutputSchema)
        if let encoded = try? JSONValue(encoding: tools) {
            return JSONRPCMessage.response(id: id, result: ["tools": encoded])
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
            // The method itself is known — a missing/non-string tool name is an
            // Invalid Params error, not the "Method not found" the nil
            // fallthrough used to produce.
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Invalid params: missing tool name")
            )
        }

        // Extract arguments from the request
        let arguments = params["arguments"]?.dictionaryValue ?? [:]

        let metadata = mcpToolMetadata(for: toolName)

        // structuredContent and resource_link are 2025-06-18 features; degrade
        // both for clients that negotiated an earlier revision.
        let profile = await RequestContext.current?.protocolProfile
        let includeStructuredContent = profile?.has(.structuredToolOutput) ?? true
        let includeResourceLinks = profile?.has(.resourceLinks) ?? true

        do {
            let result = try await toolProvider.callTool(toolName, arguments: arguments)
            let wrappedResult = try metadata?.wrapOutputIfNeeded(result) ?? result
            let expectsToolResult = metadata?.expectsToolResultReturn ?? false

            return try buildToolCallResponse(
                requestID: request.id,
                wrappedResult: wrappedResult,
                expectsToolResult: expectsToolResult,
                includeStructuredContent: includeStructuredContent,
                includeResourceLinks: includeResourceLinks
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
        expectsToolResult: Bool,
        includeStructuredContent: Bool,
        includeResourceLinks: Bool
    ) throws -> JSONRPCMessage {
        var resultPayload: JSONDictionary = [
            "isError": false
        ]

        var content: JSONValue
        var structured: JSONValue?

        if let payload = try encodeSingleContent(wrappedResult) {
            content = payload
        } else if let payload = try encodeContentArray(wrappedResult, expectsToolResult: expectsToolResult) {
            content = payload
        } else if let payload = try encodeResourceContent(wrappedResult, expectsToolResult: expectsToolResult) {
            content = payload
        } else {
            // Fallback: encode as JSON and wrap in a text content block.
            let (textContent, structuredContent) = try encodeFallbackTextContent(wrappedResult)
            content = .array([.object(textContent)])
            structured = structuredContent
        }

        // resource_link is a 2025-06-18 content type; degrade to text for older clients.
        if !includeResourceLinks {
            content = degradingResourceLinks(in: content)
        }
        resultPayload["content"] = content

        if let structured, includeStructuredContent {
            resultPayload["structuredContent"] = structured
        }
        return JSONRPCMessage.response(id: requestID, result: .object(resultPayload))
    }

    /// Rewrites any `resource_link` content blocks (a 2025-06-18 feature) into
    /// plain `text` blocks carrying the link's name and URI, for clients that
    /// negotiated an earlier revision. Non-array content is returned unchanged,
    /// so single, array and mixed tool results are all handled uniformly.
    private func degradingResourceLinks(in content: JSONValue) -> JSONValue {
        guard case .array(let items) = content else { return content }
        return .array(items.map(degradeResourceLink))
    }

    private func degradeResourceLink(_ item: JSONValue) -> JSONValue {
        guard case .object(let object) = item,
              object["type"]?.stringValue == "resource_link" else {
            return item
        }

        let uri = object["uri"]?.stringValue ?? ""
        var text = object["name"]?.stringValue.map { "\($0): \(uri)" } ?? uri
        if let description = object["description"]?.stringValue, !description.isEmpty {
            text += " — \(description)"
        }
        return .object(["type": .string("text"), "text": .string(text)])
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
