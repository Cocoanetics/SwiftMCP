import Foundation

/// Errors that can occur when calling a tool
public enum MCPToolError: Error, CustomStringConvertible {
    /// The tool with the given name doesn't exist
    case unknownTool(name: String)
    /// The tool call failed
    case callFailed(name: String, reason: String)
    /// An argument couldn't be cast to the correct type
    case invalidArgumentType(name: String, parameterName: String, expectedType: String, actualValue: Any)
    
    public var description: String {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool '\(name)'"
        case .callFailed(let name, let reason):
            return "Failed to call tool '\(name)': \(reason)"
        case .invalidArgumentType(let name, let parameterName, let expectedType, let actualValue):
            return "Failed to call tool '\(name)': Parameter '\(parameterName)' expected type '\(expectedType)' but got '\(type(of: actualValue))' with value '\(actualValue)'"
        }
    }
} 