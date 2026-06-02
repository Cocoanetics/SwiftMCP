#if Server
import Foundation

#if canImport(Network)

extension TCPBonjourTransport {
    /// Broadcasts a log message to all connected sessions.
    public func broadcastLog(_ message: LogMessage) async {
        await sessionManager.broadcastLog(message)
    }

    /// Broadcasts a tools list-changed notification to all connected sessions.
    public func broadcastToolsListChanged() async {
        await sessionManager.broadcastToolsListChanged()
    }

    /// Broadcasts a resources list-changed notification to all connected sessions.
    public func broadcastResourcesListChanged() async {
        await sessionManager.broadcastResourcesListChanged()
    }

    /// Broadcasts a prompts list-changed notification to all connected sessions.
    public func broadcastPromptsListChanged() async {
        await sessionManager.broadcastPromptsListChanged()
    }

    /// Broadcasts a resource-updated notification to all connected sessions.
    /// - Parameter uri: The URI of the resource that was updated.
    public func broadcastResourceUpdated(uri: URL) async {
        await sessionManager.broadcastResourceUpdated(uri: uri)
    }
}
#endif
#endif
