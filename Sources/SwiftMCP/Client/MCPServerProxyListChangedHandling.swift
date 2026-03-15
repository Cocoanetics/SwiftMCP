import Foundation

/// Implement to receive notifications when the server's tool list changes.
public protocol MCPServerProxyToolsListChangedHandling: AnyObject, Sendable {
    /// Called when the server notifies that its tool list has changed.
    /// - Parameters:
    ///   - proxy: The proxy that received the notification.
    func mcpServerProxyToolsListDidChange(_ proxy: MCPServerProxy) async
}

/// Implement to receive notifications when the server's resource list changes.
public protocol MCPServerProxyResourcesListChangedHandling: AnyObject, Sendable {
    /// Called when the server notifies that its resource list has changed.
    /// - Parameters:
    ///   - proxy: The proxy that received the notification.
    func mcpServerProxyResourcesListDidChange(_ proxy: MCPServerProxy) async
}

/// Implement to receive notifications when the server's prompt list changes.
public protocol MCPServerProxyPromptsListChangedHandling: AnyObject, Sendable {
    /// Called when the server notifies that its prompt list has changed.
    /// - Parameters:
    ///   - proxy: The proxy that received the notification.
    func mcpServerProxyPromptsListDidChange(_ proxy: MCPServerProxy) async
}
