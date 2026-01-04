import Foundation

/// Implement to receive log notifications sent by the server.
public protocol MCPServerProxyLogNotificationHandling: AnyObject, Sendable {
    /// Called when the proxy receives a log notification from the server.
    func mcpServerProxy(_ proxy: MCPServerProxy, didReceiveLog message: LogMessage) async
}
