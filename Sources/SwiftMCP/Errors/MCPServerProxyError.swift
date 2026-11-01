import Foundation

/// Errors that can occur when interacting with an MCP server proxy.
public enum MCPServerProxyError: Error, LocalizedError {
    case notImplemented(String)
    case communicationError(String)
    case toolError(String)
    /// A tool call the server answered with `isError: true` and `_meta`: the message, as
    /// ``toolError(_:)`` carries it, with the result's `_meta`, the details a server attached
    /// to its error (``MCPToolErrorMetaProviding``). A failed call without `_meta` is
    /// ``toolError(_:)``.
    case toolErrorWithMeta(String, meta: JSONDictionary)
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
    /// Modern-era negotiation found no revision both sides support. `supported`
    /// is the server's list (from `server/discover` or the `-32004` error data);
    /// empty when the server does not speak the modern era at all.
    case unsupportedProtocolVersion(supported: [String])
    /// The server rejected a modern request's required HTTP headers (`-32001`).
    case headerMismatch(String)
    /// A non-2xx HTTP response without a JSON-RPC error body, on a modern-era
    /// connection (legacy connections report these as ``communicationError(_:)``).
    case httpStatus(Int, String)
    /// A multi-round (`input_required`) request could not be completed.
    case inputRequired(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let message):
            return "Functionality not implemented: \(message)"
        case .communicationError(let message):
            return "Communication error with MCP server: \(message)"
        case .toolError(let message), .toolErrorWithMeta(let message, _):
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
        case .unsupportedProtocolVersion(let supported):
            let list = supported.isEmpty ? "none" : supported.joined(separator: ", ")
            return "No mutually supported modern protocol version (server supports: \(list))."
        case .httpStatus(let status, let body):
            return "Communication error with MCP server: HTTP error \(status)\(body.isEmpty ? "" : ": \(body)")"
        case .headerMismatch(let message):
            return "The server rejected the request headers: \(message)"
        case .inputRequired(let message):
            return "Multi-round request failed: \(message)"
        }
    }
}
