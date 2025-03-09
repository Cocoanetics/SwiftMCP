import Foundation

/// Errors that can occur when calling a tool
public enum MCPToolError: Error, CustomStringConvertible {
    /// The tool with the given name doesn't exist
    case unknownTool(name: String)
    /// The tool call failed
    case callFailed(name: String, reason: String)
    
    public var description: String {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool '\(name)'"
        case .callFailed(let name, let reason):
            return "Failed to call tool '\(name)': \(reason)"
        }
    }
} 