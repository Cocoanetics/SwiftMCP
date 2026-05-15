import Foundation

// MARK: - Prompts (list / get / completion)
public extension MCPServer {
    /// Creates a response listing all available prompts.
    internal func createPromptsListResponse(id: JSONRPCID) -> JSONRPCMessage {
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
        return JSONRPCMessage.errorResponse(
            id: id,
            error: .init(code: -32603, message: "Failed to encode prompts list")
        )
    }

    /// Handles a prompt get request
    internal func handlePromptGet(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard let promptProvider = self as? MCPPromptProviding else {
            return nil
        }

        guard let params = request.params,
              let name = params["name"]?.stringValue else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Missing prompt name")
            )
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
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32000, message: error.localizedDescription)
            )
        }
    }

    /// Handles a completion request for argument autocompletion.
    internal func handleCompletion(_ request: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        guard let parsed = parseCompletionRequest(request) else {
            return emptyCompletionResponse(id: request.id)
        }

        if parsed.refType == "ref/resource",
           let response = await completionResponseForResource(request: request, parsed: parsed) {
            return response
        }

        if parsed.refType == "ref/prompt",
           let response = await completionResponseForPrompt(request: request, parsed: parsed) {
            return response
        }

        return emptyCompletionResponse(id: request.id)
    }

    /// Parses the JSON-RPC completion request into the structured fields we need.
    private func parseCompletionRequest(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) -> ParsedCompletionRequest? {
        guard let params = request.params,
              let refDict = params["ref"]?.dictionaryValue,
              let argDict = params["argument"]?.dictionaryValue,
              let argName = argDict["name"]?.stringValue else {
            return nil
        }

        return ParsedCompletionRequest(
            refType: refDict["type"]?.stringValue,
            refDict: refDict,
            argName: argName,
            prefix: argDict["value"]?.stringValue ?? ""
        )
    }

    /// Builds a completion response for a `ref/resource` reference, if it matches a known template.
    private func completionResponseForResource(
        request: JSONRPCMessage.JSONRPCRequestData,
        parsed: ParsedCompletionRequest
    ) async -> JSONRPCMessage? {
        guard let uri = parsed.refDict["uri"]?.stringValue,
              let resourceProvider = self as? MCPResourceProviding,
              let metadata = resourceProvider.mcpResourceMetadata.first(
                where: { $0.uriTemplates.contains(uri) }
              ),
              let parameter = metadata.parameters.first(where: { $0.name == parsed.argName }) else {
            return nil
        }

        let comp = await completion(for: parameter, in: .resource(metadata), prefix: parsed.prefix)
        return completionResponse(id: request.id, comp: comp)
    }

    /// Builds a completion response for a `ref/prompt` reference, if it matches a known prompt.
    private func completionResponseForPrompt(
        request: JSONRPCMessage.JSONRPCRequestData,
        parsed: ParsedCompletionRequest
    ) async -> JSONRPCMessage? {
        guard let name = parsed.refDict["name"]?.stringValue,
              let promptProvider = self as? MCPPromptProviding,
              let metadata = promptProvider.mcpPromptMetadata.first(where: { $0.name == name }),
              let parameter = metadata.parameters.first(where: { $0.name == parsed.argName }) else {
            return nil
        }

        let comp = await completion(for: parameter, in: .prompt(metadata), prefix: parsed.prefix)
        return completionResponse(id: request.id, comp: comp)
    }

    /// Resolves a completion value either via the user-provided `MCPCompletionProviding`
    /// implementation or by falling back to the parameter's default completions.
    private func completion(
        for parameter: MCPParameterInfo,
        in context: MCPCompletionContext,
        prefix: String
    ) async -> CompleteResult.Completion {
        if let completionProvider = self as? MCPCompletionProviding {
            return await completionProvider.completion(
                for: parameter,
                in: context,
                prefix: prefix
            )
        }
        let completions = parameter.defaultCompletions.sortedByBestCompletion(prefix: prefix)
        return CompleteResult.Completion(values: completions, total: completions.count, hasMore: false)
    }

    /// Encodes a `CompleteResult.Completion` into the standard JSON-RPC completion response.
    private func completionResponse(
        id: JSONRPCID,
        comp: CompleteResult.Completion
    ) -> JSONRPCMessage {
        let result: JSONDictionary = [
            "completion": .object([
                "values": .array(comp.values.map { .string($0) }),
                "total": .integer(comp.total ?? comp.values.count),
                "hasMore": .bool(comp.hasMore ?? false)
            ])
        ]
        return JSONRPCMessage.response(id: id, result: result)
    }

    /// Empty completion fallback used when the request doesn't map onto any known resource/prompt.
    private func emptyCompletionResponse(id: JSONRPCID) -> JSONRPCMessage {
        JSONRPCMessage.response(
            id: id,
            result: ["completion": .object(["values": .array([])])]
        )
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

/// Parsed `completion/complete` payload used by the prompt-completion handler.
private struct ParsedCompletionRequest {
    let refType: String?
    let refDict: JSONDictionary
    let argName: String
    let prefix: String
}
