import Foundation

/// Errors that can occur when calling a tool
public enum MCPToolError: Error {
	/// The tool with the given name doesn't exist
	case unknownTool(name: String)

	/// An argument couldn't be cast to the correct type
	case invalidArgumentType(parameterName: String, expectedType: String, actualType: String)

	/// An argument couldn't be cast to the correct type
	case invalidEnumValue(parameterName: String, expectedValues: [String], actualValue: String)

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
			case .invalidArgumentType(let parameterName, let expectedType, let actualType):
				return "Parameter '\(parameterName)' expected type \(expectedType) but received type \(actualType)"
			case .invalidEnumValue(let parameterName, let expectedValues, let actualValue):
				let string = expectedValues.joined(separator: ", ")
				return "Parameter '\(parameterName)' expected one of [\(string)] but received \(actualValue)"
			case .invalidJSONDictionary:
				return "The input could not be parsed as a valid JSON dictionary"
			case .missingRequiredParameter(let parameterName):
				return "Missing required parameter '\(parameterName)'"
		}
	}
}
