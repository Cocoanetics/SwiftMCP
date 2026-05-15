import Foundation

extension HTTPSSETransport {
    /// Broadcast a log message to all connected clients.
    /// - Parameter message: The log message to broadcast
    public func broadcastLog(_ message: LogMessage) async {
        // Send to all connected sessions, filtered by their minimumLogLevel
        await sessionManager.broadcastLog(message)
    }

    /// Broadcast a tools list-changed notification to all connected clients.
    public func broadcastToolsListChanged() async {
        await sessionManager.broadcastToolsListChanged()
    }

    /// Broadcast a resources list-changed notification to all connected clients.
    public func broadcastResourcesListChanged() async {
        await sessionManager.broadcastResourcesListChanged()
    }

    /// Broadcast a prompts list-changed notification to all connected clients.
    public func broadcastPromptsListChanged() async {
        await sessionManager.broadcastPromptsListChanged()
    }

    /// Broadcast a resource-updated notification to all connected clients.
    /// - Parameter uri: The URI of the resource that was updated.
    public func broadcastResourceUpdated(uri: URL) async {
        await sessionManager.broadcastResourceUpdated(uri: uri)
    }
}
