import Foundation

// MARK: - Initialize / Ping
public extension MCPServer {
    /**
     Handles an initialization request from the client.

     This processes the client capabilities and client info, stores them in the current session,
     then creates and returns an initialization response.

     - Parameter request: The initialization request data
     - Returns: A JSON-RPC message containing the initialization response
     */
    internal func handleInitializeRequest(
        _ request: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        await Session.current?.markInitializeRequestReceived()
        let negotiatedProtocolVersion = request.params?["protocolVersion"]?.stringValue
            ?? HTTPSSETransport.latestProtocolVersion
        guard HTTPSSETransport.supportedProtocolVersions.contains(negotiatedProtocolVersion) else {
            return JSONRPCMessage.errorResponse(
                id: request.id,
                error: .init(code: -32602, message: "Unsupported protocol version: \(negotiatedProtocolVersion)")
            )
        }
        await Session.current?.setNegotiatedProtocolVersion(negotiatedProtocolVersion)
        await extractAndStoreCapabilities(request)
        await extractAndStoreClientInfo(request)
        // Extract and store authentication metadata from _meta
        if let meta = RequestContext.current?.meta {
            if let accessToken = meta.accessToken {
                await Session.current?.setAccessToken(accessToken)
            }
        }

        return await createInitializeResponse(id: request.id, protocolVersion: negotiatedProtocolVersion)
    }

    internal func extractAndStoreCapabilities(_ request: JSONRPCMessage.JSONRPCRequestData) async {
        if let params = request.params,
           let capabilitiesValue = params["capabilities"],
           let clientCapabilities: ClientCapabilities = try? capabilitiesValue.decoded(ClientCapabilities.self) {
            if let session = Session.current {
                await session.setClientCapabilities(clientCapabilities)
            }
        }
    }

    internal func extractAndStoreClientInfo(_ request: JSONRPCMessage.JSONRPCRequestData) async {
        if let params = request.params,
           let clientInfoValue = params["clientInfo"],
           let clientInfo: Implementation = try? clientInfoValue.decoded(Implementation.self) {
            if let session = Session.current {
                await session.setClientInfo(clientInfo)
            }
        }
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
    func createInitializeResponse(
        id: JSONRPCID,
        protocolVersion: String = "2025-11-25"
    ) async -> JSONRPCMessage {
        let capabilities = await buildServerCapabilities()

        let serverInfo = InitializeResult.ServerInfo(
            name: serverName,
            version: serverVersion,
            description: serverDescription
        )

        let result = InitializeResult(
            protocolVersion: protocolVersion,
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

    /// Builds the `ServerCapabilities` advertised in an initialize response, only
    /// flagging tools/resources/prompts when there is actual content to expose.
    internal func buildServerCapabilities() async -> ServerCapabilities {
        var capabilities = ServerCapabilities()

        // Advertise tools/resources/prompts capabilities only when there is
        // actual content to expose. Every `@MCPServer` now unconditionally
        // conforms to all three `*Providing` protocols (so `@MCPExtension`
        // contributions of any kind can land at runtime), so conformance
        // alone is no longer a meaningful signal — a server with no local
        // declarations and no registered extensions would otherwise claim
        // capabilities it can't actually fulfill.
        if let toolProvider = self as? MCPToolProviding,
           !(await toolProvider.mcpToolMetadata).isEmpty {
            capabilities.tools = .init(listChanged: true)
        }

        if let resourceProvider = self as? MCPResourceProviding,
           !(await resourceProvider.mcpResourceMetadata).isEmpty {
            capabilities.resources = .init(subscribe: true, listChanged: true)
        }

        if let promptProvider = self as? MCPPromptProviding,
           !(await promptProvider.mcpPromptMetadata).isEmpty {
            capabilities.prompts = .init(listChanged: true)
        }

        if self is MCPLoggingProviding {
            capabilities.logging = .init(enabled: true)
        }

        // Advertise completion support
        capabilities.completions = .object([:])

        return capabilities
    }

    /**
     Creates a ping response with empty result.

     - Parameter id: The request ID to include in the response
     - Returns: A JSON-RPC response for ping
     */
    func createPingResponse(id: JSONRPCID) -> JSONRPCMessage {
        return JSONRPCMessage.response(id: id, result: [:])
    }
}
