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
        }
    }
}
