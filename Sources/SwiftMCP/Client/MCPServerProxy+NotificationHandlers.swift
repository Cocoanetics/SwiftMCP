import Foundation

extension MCPServerProxy {
    /// Updates the log notification handler.
    public func setLogNotificationHandler(
        _ handler: (any MCPServerProxyLogNotificationHandling)?
    ) {
        logNotificationHandler = handler
    }

    /// Updates the progress notification handler.
    public func setProgressNotificationHandler(
        _ handler: (any MCPServerProxyProgressNotificationHandling)?
    ) {
        progressNotificationHandler = handler
    }

    /// Updates the resource notification handler.
    public func setResourceNotificationHandler(
        _ handler: (any MCPServerProxyResourceNotificationHandling)?
    ) {
        resourceNotificationHandler = handler
    }

    /// Updates the tools list-changed handler.
    public func setToolsListChangedHandler(
        _ handler: (any MCPServerProxyToolsListChangedHandling)?
    ) {
        toolsListChangedHandler = handler
    }

    /// Updates the resources list-changed handler.
    public func setResourcesListChangedHandler(
        _ handler: (any MCPServerProxyResourcesListChangedHandling)?
    ) {
        resourcesListChangedHandler = handler
    }

    /// Updates the prompts list-changed handler.
    public func setPromptsListChangedHandler(
        _ handler: (any MCPServerProxyPromptsListChangedHandling)?
    ) {
        promptsListChangedHandler = handler
    }

    /// Registers a typed handler for a JSON-RPC notification.
    public func setNotificationHandler<Payload>(
        _ method: String,
        as payloadType: Payload.Type = Payload.self,
        handler: @escaping @Sendable (Payload) async -> Void
    ) where Payload: Decodable, Payload: Sendable {
        notificationHandlers[method] = NotificationHandlerBox(
            payloadTypeDescription: String(reflecting: payloadType),
            handle: { _, notification in
                let payload = try Self.decodeNotificationPayload(
                    from: notification,
                    as: payloadType
                )
                await handler(payload)
            }
        )
    }

    /// Removes the registered handler for a JSON-RPC notification.
    public func removeNotificationHandler(for method: String) {
        notificationHandlers.removeValue(forKey: method)
    }
}
