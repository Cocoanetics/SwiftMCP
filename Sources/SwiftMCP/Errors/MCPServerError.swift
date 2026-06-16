import Foundation

/// Errors that can occur during MCP server operations.
public enum MCPServerError: LocalizedError {
    /// No active session is available.
    case noActiveSession

    /// No active request context is available.
    case noActiveRequestContext

    /// The client does not support roots functionality.
    case clientHasNoRootsSupport

    /// The client does not support sampling functionality.
    case clientHasNoSamplingSupport

    /// The client does not support elicitation functionality.
    case clientHasNoElicitationSupport

    /// The negotiated protocol revision does not include the requested feature,
    /// so the server must not exercise it (e.g. `elicitation/create` against a
    /// client that negotiated a pre-`2025-06-18` revision).
    case featureUnavailableInNegotiatedVersion(feature: MCPFeature, version: String)

    /// Client returned an error response with specific code and message.
    case clientError(code: Int, message: String)

    /// Received an unexpected message type from the client.
    case unexpectedMessageType(method: String)

    public var errorDescription: String? {
        switch self {
        case .noActiveSession:
            return "No active session available"
        case .noActiveRequestContext:
            return "No active request context available"
        case .clientHasNoRootsSupport:
            return "Client does not support roots functionality"
        case .clientHasNoSamplingSupport:
            return "Client does not support sampling functionality"
        case .clientHasNoElicitationSupport:
            return "Client does not support elicitation functionality"
        case .featureUnavailableInNegotiatedVersion(let feature, let version):
            return "The negotiated protocol version \(version) does not support \(feature.rawValue)"
        case .clientError(let code, let message):
            return "Client error \(code): \(message)"
        case .unexpectedMessageType(let method):
            return "Unexpected message type received for method: \(method)"
        }
    }
}
