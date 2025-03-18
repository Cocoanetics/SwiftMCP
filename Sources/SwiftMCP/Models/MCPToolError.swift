import Foundation

/// Errors that can occur when calling a tool
public enum MCPToolError: Error {
	/// The tool with the given name doesn't exist
	case unknownTool(name: String)

	/// The tool call failed
	case callFailed(name: String, reason: String)

	/// An argument couldn't be cast to the correct type
	case invalidArgumentType(parameterName: String, expectedType: String, actualValue: Any)

	/// The input is not a valid JSON dictionary
	case invalidJSONDictionary

	/// A required parameter is missing
	case missingRequiredParameter(parameterName: String)
}

extension MCPToolError: LocalizedError {
	public var errorDescription: String? {
		switch self {
			case .unknownTool(let name):
				return "The tool '\(name)' was not found on the server"
			case .callFailed(let name, let reason):
				return "The tool '\(name)' failed to execute: \(reason)"
			case .invalidArgumentType(let parameterName, let expectedType, let actualValue):
				return "Parameter '\(parameterName)' expected type \(expectedType) but received \(type(of: actualValue)) with value '\(actualValue)'"
			case .invalidJSONDictionary:
				return "The input could not be parsed as a valid JSON dictionary"
			case .missingRequiredParameter(let parameterName):
				return "Missing required parameter '\(parameterName)'"
		}
	}
}
