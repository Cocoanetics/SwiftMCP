import Foundation

/// Carries the non-Sendable `MCPServer` existential into the cancellable
/// request task. See the comment in `processCancellableRequest` for why the
/// sharing is sound.
private struct UncheckedServerBox: @unchecked Sendable {
    let server: any MCPServer
}

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
                return await processCancellableRequest(requestData)

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
     Runs `handleRequest` as a task registered with the session under the
     request id, making the request cancellable from outside:

     - `notifications/cancelled` looks the id up on the session and cancels it.
     - A transport tearing down a disconnected connection cancels the dispatch
       task, and the handler forwards that cancellation into the request task —
       so a long-running tool body stops instead of working for a client that
       is gone.

     The task is unstructured on purpose (a structured child cannot be
     cancelled from outside), but inherits the `Session`/`RequestContext`
     task-locals. Without a current session there is nobody to deliver a
     cancellation, so the request runs directly.

     - Parameter requestData: The request data
     - Returns: The response, or nil when the request was cancelled (its
       response must be suppressed per the MCP cancellation spec)
     */
    internal func processCancellableRequest(
        _ requestData: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        guard let session = Session.current else {
            return await handleRequest(requestData)
        }

        // `MCPServer` is not statically Sendable, but every transport already
        // dispatches into it from concurrent per-connection tasks (through
        // `@unchecked Sendable` transports) — concurrent use is the de-facto
        // contract of server implementations. The unstructured task moves the
        // same call one task deeper; it adds no new kind of sharing. Boxed (and
        // erased, so the generic `Self.Type` metatype is not captured either)
        // to carry it past the `sending` closure check.
        let box = UncheckedServerBox(server: self)
        let task = Task { await box.server.handleRequest(requestData) }
        await session.registerInFlightRequest(id: requestData.id) { task.cancel() }

        let response = await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }

        let wasCancelled = await session.unregisterInFlightRequest(id: requestData.id)
        return wasCancelled ? nil : response
    }

    /**
     Handles JSON-RPC requests that expect responses.

     - Parameter requestData: The request data
     - Returns: A response message if one should be sent, nil otherwise
     */
    internal func handleRequest(_ requestData: JSONRPCMessage.JSONRPCRequestData) async -> JSONRPCMessage? {
        // Modern negotiation guard: a request that carries a `_meta`
        // `protocolVersion` this server cannot serve is rejected with `-32004`,
        // naming the versions it can negotiate. "Servable" is broader than
        // "advertised": a known modern revision (`2026-07-28`) reaches the modern
        // path even while it is kept out of `supported`, so only unknown /
        // non-negotiable versions are rejected here. `server/discover` is exempt —
        // it is the negotiation entry point and must always answer. Legacy requests
        // never set this `_meta` key, so this never fires for them.
        if requestData.method != "server/discover",
           let requested = RequestContext.current?.meta?.protocolVersion,
           !MCPProtocolVersion.isServable(requested) {
            return unsupportedProtocolVersionError(id: requestData.id, requested: requested)
        }

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
    ///
    /// See ``ModernRequestMethods`` below for the modern-era request surface the
    /// HTTP route layer checks before dispatch.
    private func dispatchInitializationOrMetaRequest(
        _ requestData: JSONRPCMessage.JSONRPCRequestData
    ) async -> JSONRPCMessage? {
        switch requestData.method {
        case "initialize":
            return await handleInitializeRequest(requestData)
        case "server/discover":
            return await handleServerDiscoverRequest(requestData)
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
            return await createToolsListResponse(id: requestData.id)
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
            return await createPromptsListResponse(id: requestData.id)
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
            // Client has cancelled a request — cancel it if it is still running.
            await handleCancelledNotification(notificationData)
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

    /// Cancels the in-flight request identified by a `notifications/cancelled`
    /// notification on the current session. `requestId` may be a string or an
    /// integer; unknown ids are a no-op per the MCP cancellation spec.
    private func handleCancelledNotification(
        _ notificationData: JSONRPCMessage.JSONRPCNotificationData
    ) async {
        guard let session = Session.current,
              case .object(let params)? = notificationData.params else {
            return
        }

        let requestID: JSONRPCID
        switch params["requestId"] {
        case .string(let value):
            requestID = .string(value)
        case .integer(let value):
            requestID = .integer(value)
        default:
            return
        }

        await session.cancelInFlightRequest(id: requestID)
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

/// The request methods a modern (`2026-07-28`) client may call — the closed
/// modern-era surface of the dispatch functions above. The HTTP route layer
/// consults this *before* dispatch so an unknown modern method can be answered
/// with HTTP `404` + `-32601` (the per-request SSE stream commits the status
/// before dispatch completes, so the decision cannot wait for the in-band
/// fallback).
///
/// Deliberately excluded (legacy-only per `ProtocolVersionProfile`):
/// `initialize`, `ping`, `logging/setLevel`, `resources/subscribe` /
/// `resources/unsubscribe`. `subscriptions/listen` joins when Phase 4 implements
/// it. Keep in sync with the `dispatch*Request` functions — the
/// "modern method surface matches the dispatcher" test enforces this.
enum ModernRequestMethods {
    static let known: Set<String> = [
        "server/discover",
        "tools/list", "tools/call",
        "resources/list", "resources/templates/list", "resources/read",
        "prompts/list", "prompts/get",
        "completion/complete"
    ]
}
