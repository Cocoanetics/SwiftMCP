import Foundation

// MARK: - Resources (list / read / templates / subscribe)
public extension MCPServer {
    /**
     Creates a response listing all available resources.

     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC message containing the resources list
     */
    func createResourcesListResponse(id: JSONRPCID) async -> JSONRPCMessage {
        guard let resourceProvider = self as? MCPResourceProviding else {
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
        return JSONRPCMessage.errorResponse(
            id: id,
            error: .init(code: -32603, message: "Failed to encode resources list")
        )
    }

    /**
     Creates a response for a resource read request.

     - Parameters:
       - id: The request ID to include in the response
       - request: The original JSON-RPC request
     - Returns: A JSON-RPC message containing the resource content or an error
     */
    func createResourcesReadResponse(
        id: JSONRPCID,
        request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage {
        guard let resourceProvider = self as? MCPResourceProviding else {
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
            return JSONRPCMessage.errorResponse(
                id: id,
                error: .init(code: -32602, message: "Invalid or missing URI parameter")
            )
        }

        // MRTR (modern): verify an echoed requestState and stage the retry's
        // input responses before execution.
        if let rejection = await mrtrPrepareExecution(request) {
            return rejection
        }

        do {
            // Try to get the resource content
            let resourceContentArray = try await resourceProvider.getResource(uri: uri)

            if !resourceContentArray.isEmpty {
                let contents = try resourceContentArray.map { try JSONValue(encoding: $0) }
                return JSONRPCMessage.response(id: id, result: ["contents": .array(contents)])
            } else {
                // The not-found code is version-sensitive: modern revisions align
                // with JSON-RPC and use -32602 (Invalid Params); legacy keeps
                // SwiftMCP's historical -32001.
                return await Self.resourceNotFoundResponse(id: id, uri: uri.absoluteString)
            }
        } catch let signal as InputRequiredSignal {
            // MRTR (modern): the resource needs client input — answer
            // input_required and let the client retry with the responses.
            return await mrtrInputRequiredResponse(for: signal, request: request)
        } catch let invalid as MRTRInvalidInputResponse {
            return mrtrInvalidInputResponse(for: invalid, request: request)
        } catch MCPResourceError.notFound(let missingURI) {
            // A provider that *throws* not-found means the same thing as one that
            // returns no content — both use the version-sensitive not-found code
            // instead of a generic -32000.
            return await Self.resourceNotFoundResponse(id: id, uri: missingURI)
        } catch {
            return JSONRPCMessage.errorResponse(
                id: id,
                error: .init(
                    code: -32000,
                    message: "Error getting resource: \(error.localizedDescription)"
                )
            )
        }
    }

    /// The version-sensitive resource-not-found error: modern aligns with
    /// JSON-RPC (`-32602` Invalid Params); legacy keeps SwiftMCP's historical
    /// `-32001`.
    internal static func resourceNotFoundResponse(id: JSONRPCID, uri: String) async -> JSONRPCMessage {
        let profile = await RequestContext.current?.protocolProfile ?? .v20251125
        return JSONRPCMessage.errorResponse(
            id: id,
            error: .init(
                code: profile.resourceNotFoundCode,
                message: "Resource not found: \(uri)"
            )
        )
    }

    /**
     Creates a response listing all available resource templates.

     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC response containing the resource templates list
     */
    func createResourceTemplatesListResponse(id: JSONRPCID) async -> JSONRPCMessage {
        guard let resourceProvider = self as? MCPResourceProviding else {
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
        return JSONRPCMessage.errorResponse(
            id: id,
            error: .init(code: -32603, message: "Failed to encode resource templates list")
        )
    }

    // MARK: - Resource Subscriptions

    internal func handleResourceSubscribe(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        // Only honor subscriptions when the server actually exposes resources.
        // The `@MCPServer` macro always adds `MCPResourceProviding` conformance
        // (so extension-contributed resources can surface), so conformance alone
        // is not a reliable signal. `exposesResources` covers both `@MCPResource`
        // metadata and the dynamic `mcpResources` path, matching exactly what the
        // `resources` capability advertises during initialize.
        guard let resourceProvider = self as? MCPResourceProviding,
              await resourceProvider.exposesResources else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32601, message: "Server does not support resource subscriptions")
            )
        }

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

    internal func handleResourceUnsubscribe(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        guard let resourceProvider = self as? MCPResourceProviding,
              await resourceProvider.exposesResources else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32601, message: "Server does not support resource subscriptions")
            )
        }

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
}
