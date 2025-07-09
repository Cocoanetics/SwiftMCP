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
        case .clientError(let code, let message):
            return "Client error \(code): \(message)"
        case .unexpectedMessageType(let method):
            return "Unexpected message type received for method: \(method)"
        }
    }
} 