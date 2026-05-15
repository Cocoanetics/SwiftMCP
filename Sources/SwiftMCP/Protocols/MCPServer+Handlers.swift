import Foundation

// MARK: - JSON-RPC Message Dispatch
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
    internal func handleRequest(_ requestData: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        if let response = await dispatchInitializationOrMetaRequest(requestData) {
            return response
        }
        if let response = await dispatchToolRequest(requestData) {
            return response
        }
        if let response = await dispatchResourceRequest(requestData) {
            return response
        }
        if let response = await dispatchPromptRequest(requestData) {
            return response
        }
        if let response = await dispatchLoggingRequest(requestData) {
            return response
        }

        // Respond with JSON-RPC error for method not found
        return JSONRPCMessage.errorResponse(
            id: requestData.id,
            error: .init(code: -32601, message: "Method not found")
        )
    }

    /// Handles `initialize` / `ping` requests.
    private func dispatchInitializationOrMetaRequest(
        _ requestData: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        switch requestData.method {
        case "initialize":
            return await handleInitializeRequest(requestData)
        case "ping":
            return createPingResponse(id: requestData.id)
        default:
            return nil
        }
    }

    /// Handles `tools/list` and `tools/call`.
    private func dispatchToolRequest(
        _ requestData: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        switch requestData.method {
        case "tools/list":
            return createToolsListResponse(id: requestData.id)
        case "tools/call":
            return await handleToolCall(requestData)
        default:
            return nil
        }
    }

    /// Handles all `resources/*` requests.
    private func dispatchResourceRequest(
        _ requestData: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        switch requestData.method {
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
        default:
            return nil
        }
    }

    /// Handles `prompts/*` and `completion/complete` requests.
    private func dispatchPromptRequest(
        _ requestData: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        switch requestData.method {
        case "prompts/list":
            return createPromptsListResponse(id: requestData.id)
        case "prompts/get":
            return await handlePromptGet(requestData)
        case "completion/complete":
            return await handleCompletion(requestData)
        default:
            return nil
        }
    }

    /// Handles `logging/*` requests.
    private func dispatchLoggingRequest(
        _ requestData: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        switch requestData.method {
        case "logging/setLevel":
            return await handleLoggingSetLevel(requestData)
        default:
            return nil
        }
    }

    /**
     Handles JSON-RPC notifications (no response expected).

     - Parameter notificationData: The notification data
     - Returns: Always returns nil since notifications don't expect responses
     */
    internal func handleNotification(
        _ notificationData: JSONRPCMessage.JSONRPCNotificationData
    ) async -> JSONRPCMessage? {
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

    /**
     Handles JSON-RPC responses from other parties.

     - Parameter responseData: The response data
     - Returns: Always returns nil since we don't currently respond to responses
     */
    internal func handleResponse(_ responseData: JSONRPCMessage.JSONRPCResponseData) async -> JSONRPCMessage? {
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
    internal func handleErrorResponse(
        _ errorResponseData: JSONRPCMessage.JSONRPCErrorResponseData
    ) async -> JSONRPCMessage? {
        // Route the error response to the current session for request/response matching
        let response = JSONRPCMessage.errorResponse(errorResponseData)
        if let session = Session.current {
            await session.handleResponse(response)
        }
        return nil
    }
}
