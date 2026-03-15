import Foundation

/// Implement to receive notifications when a subscribed resource has been updated.
public protocol MCPServerProxyResourceNotificationHandling: AnyObject, Sendable {
    /// Called when a subscribed resource has been updated on the server.
    /// - Parameters:
    ///   - proxy: The proxy that received the notification.
    ///   - uri: The URI of the resource that was updated.
    func mcpServerProxy(_ proxy: MCPServerProxy, resourceUpdatedAt uri: URL) async
}
