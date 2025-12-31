import Foundation

/// Errors that can occur when interacting with an MCP server proxy.
public enum MCPServerProxyError: Error, LocalizedError {
    case notImplemented(String)
    case communicationError(String)
    case unsupportedPlatform(String)

    public var errorDescription: String? {
        switch self {
        case .notImplemented(let message):
            return "Functionality not implemented: \(message)"
        case .communicationError(let message):
            return "Communication error with MCP server: \(message)"
        case .unsupportedPlatform(let message):
            return "Unsupported platform: \(message)"
        }
    }
}
