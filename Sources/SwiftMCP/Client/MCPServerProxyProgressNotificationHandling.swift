import Foundation

/// Implement to receive progress notifications sent by the server.
public protocol MCPServerProxyProgressNotificationHandling: AnyObject, Sendable {
    /// Called when the proxy receives a progress notification from the server.
    func mcpServerProxy(_ proxy: MCPServerProxy, didReceiveProgress progress: ProgressNotification) async
}
