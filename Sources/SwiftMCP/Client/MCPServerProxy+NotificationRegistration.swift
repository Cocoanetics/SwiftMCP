#if Client
import Foundation

extension MCPServerProxy {
    internal func updateLogNotificationRegistration() {
        guard let handler = logNotificationHandler else {
            removeNotificationHandler(for: NotificationMethod.log)
            return
        }

        notificationHandlers[NotificationMethod.log] = NotificationHandlerBox(
            payloadTypeDescription: String(reflecting: LogMessage.self),
            handle: { proxy, notification in
                let message = try Self.decodeNotificationPayload(
                    from: notification,
                    as: LogMessage.self
                )
                await handler.mcpServerProxy(proxy, didReceiveLog: message)
            }
        )
    }

    internal func updateProgressNotificationRegistration() {
        guard let handler = progressNotificationHandler else {
            removeNotificationHandler(for: NotificationMethod.progress)
            return
        }

        notificationHandlers[NotificationMethod.progress] = NotificationHandlerBox(
            payloadTypeDescription: String(reflecting: ProgressNotification.self),
            handle: { proxy, notification in
                let progress = try Self.decodeNotificationPayload(
                    from: notification,
                    as: ProgressNotification.self
                )
                await handler.mcpServerProxy(proxy, didReceiveProgress: progress)
            }
        )
    }

    // MARK: - Resource Updated Registration

    internal func updateResourceNotificationRegistration() {
        guard let handler = resourceNotificationHandler else {
            removeNotificationHandler(for: NotificationMethod.resourceUpdated)
            return
        }

        notificationHandlers[NotificationMethod.resourceUpdated] = NotificationHandlerBox(
            payloadTypeDescription: "ResourceUpdated",
            handle: { proxy, notification in
                let params = try Self.decodeNotificationPayload(
                    from: notification,
                    as: ResourceUpdatedParams.self
                )
                guard let url = URL(string: params.uri) else { return }
                await handler.mcpServerProxy(proxy, resourceUpdatedAt: url)
            }
        )
    }

    // MARK: - List Changed Registration

    internal func updateToolsListChangedRegistration() {
        guard let handler = toolsListChangedHandler else {
            removeNotificationHandler(for: NotificationMethod.toolsListChanged)
            return
        }

        notificationHandlers[NotificationMethod.toolsListChanged] = NotificationHandlerBox(
            payloadTypeDescription: "ToolsListChanged",
            handle: { proxy, _ in
                await handler.mcpServerProxyToolsListDidChange(proxy)
            }
        )
    }

    internal func updateResourcesListChangedRegistration() {
        guard let handler = resourcesListChangedHandler else {
            removeNotificationHandler(for: NotificationMethod.resourcesListChanged)
            return
        }

        notificationHandlers[NotificationMethod.resourcesListChanged] = NotificationHandlerBox(
            payloadTypeDescription: "ResourcesListChanged",
            handle: { proxy, _ in
                await handler.mcpServerProxyResourcesListDidChange(proxy)
            }
        )
    }

    internal func updatePromptsListChangedRegistration() {
        guard let handler = promptsListChangedHandler else {
            removeNotificationHandler(for: NotificationMethod.promptsListChanged)
            return
        }

        notificationHandlers[NotificationMethod.promptsListChanged] = NotificationHandlerBox(
            payloadTypeDescription: "PromptsListChanged",
            handle: { proxy, _ in
                await handler.mcpServerProxyPromptsListDidChange(proxy)
            }
        )
    }

    // MARK: - Client Capabilities

    /// Builds the client capabilities dictionary based on installed handlers.
    /// Only advertises support for features that have handlers installed.
    internal func buildClientCapabilities() -> JSONDictionary {
        var capabilities: JSONDictionary = [:]

        // Resource capabilities — subscription and/or list-changed
        var resourcesCap: JSONDictionary = [:]
        if resourceNotificationHandler != nil {
            resourcesCap["subscribe"] = .bool(true)
        }
        if resourcesListChangedHandler != nil {
            resourcesCap["listChanged"] = .bool(true)
        }
        if !resourcesCap.isEmpty {
            capabilities["resources"] = .object(resourcesCap)
        }

        // Tools list-changed
        if toolsListChangedHandler != nil {
            capabilities["tools"] = .object(["listChanged": .bool(true)])
        }

        // Prompts list-changed
        if promptsListChangedHandler != nil {
            capabilities["prompts"] = .object(["listChanged": .bool(true)])
        }

        return capabilities
    }

    internal static func decodeNotificationPayload<Payload>(
        from notification: JSONRPCMessage.JSONRPCNotificationData,
        as payloadType: Payload.Type = Payload.self
    ) throws -> Payload where Payload: Decodable {
        let params = notification.params ?? [:]
        return try decodeJSONPayload(params, as: payloadType)
    }
}
#endif
