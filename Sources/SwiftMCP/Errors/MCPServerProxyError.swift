import Foundation

/// Errors that can occur when interacting with an MCP server proxy.
public enum MCPServerProxyError: Error, LocalizedError {
    case notImplemented(String)
    case communicationError(String)
    case toolError(String)
    case unsupportedPlatform(String)
    /// The server no longer recognizes this session (it returned HTTP 404 to a
    /// request that carried an `Mcp-Session-Id`), typically because the server
    /// was restarted and lost its in-memory session table. The existing session
    /// is dead and cannot be revived by retrying; the proxy must reconnect (call
    /// `connect()` again, or create a fresh proxy) to obtain a new session.
    case sessionInvalidated
    /// No MCP service with the requested name appeared within the timeout.
    ///
    /// Distinct from a bare timeout: the browse ran and found nothing matching,
    /// which points at the server not running rather than at the network.
    case serviceNotFound(instanceName: String?)
    /// A nameless browse found more than one MCP service, so there is no single
    /// right answer. Name the one you want, or browse and choose.
    case ambiguousService(candidates: [String])
    /// The advertised publisher process is gone — a stale or wedged advertisement.
    case publisherNotRunning(processID: Int32)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let message):
            return "Functionality not implemented: \(message)"
        case .communicationError(let message):
            return "Communication error with MCP server: \(message)"
        case .toolError(let message):
            return "Tool call failed: \(message)"
        case .unsupportedPlatform(let message):
            return "Unsupported platform: \(message)"
        case .sessionInvalidated:
            return "MCP session is no longer valid; reconnect to start a new session."
        case .serviceNotFound(let instanceName):
            if let instanceName {
                return "No MCP service named \"\(instanceName)\" was found. Is the server running?"
            }
            return "No MCP service was found. Is the server running?"
        case .ambiguousService(let candidates):
            return """
                Several MCP services are available (\(candidates.joined(separator: ", "))). \
                Specify which one to connect to.
                """
        case .publisherNotRunning(let processID):
            return "The advertised MCP server (pid \(processID)) is no longer running."
        }
    }
}
