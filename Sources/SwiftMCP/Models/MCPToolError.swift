import Foundation

/// Errors that can occur when calling a tool
public enum MCPToolError: Error, CustomStringConvertible, LocalizedError {
    /// The tool with the given name doesn't exist
    case unknownTool(name: String)
    /// The tool call failed
    case callFailed(name: String, reason: String)
    /// An argument couldn't be cast to the correct type
    case invalidArgumentType(name: String, parameterName: String, expectedType: String, actualValue: Any)
    /// The input is not a valid JSON dictionary
    case invalidJSONDictionary(reason: String)
    /// A required parameter is missing
    case missingRequiredParameter(parameterName: String)
    
    public var description: String {
        switch self {
        case .unknownTool(let name):
            return "Unknown tool '\(name)'"
        case .callFailed(let name, let reason):
            return "Failed to call tool '\(name)': \(reason)"
        case .invalidArgumentType(let name, let parameterName, let expectedType, let actualValue):
            return "Parameter '\(parameterName)' expected type '\(expectedType)' but got '\(type(of: actualValue))' with value '\(actualValue)'"
        case .invalidJSONDictionary(let reason):
            return "Invalid JSON dictionary: \(reason)"
        case .missingRequiredParameter(let parameterName):
            return "Missing required parameter '\(parameterName)'"
        }
    }
    
    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "The tool '\(name)' was not found on the server"
        case .callFailed(let name, let reason):
            return "The tool '\(name)' failed to execute: \(reason)"
        case .invalidArgumentType(let name, let parameterName, let expectedType, let actualValue):
            return "Parameter '\(parameterName)' expected type \(expectedType) but received \(type(of: actualValue)) with value '\(actualValue)'"
        case .invalidJSONDictionary(let reason):
            return "The input could not be parsed as a valid JSON dictionary: \(reason)"
        case .missingRequiredParameter(let parameterName):
            return "Missing required parameter '\(parameterName)'"
        }
    }
} 
