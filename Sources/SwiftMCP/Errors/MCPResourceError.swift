import Foundation

/// Errors that can occur when working with MCP resources
public enum MCPResourceError: LocalizedError {
    /// The requested resource was not found
    case notFound(uri: String)
    
    /// The URI template does not match the provided URI
    case templateMismatch(template: String, uri: String)
    
    /// A required parameter is missing
    case missingParameter(name: String)
    
    /// Parameter type conversion failed
    case typeMismatch(parameter: String, expectedType: String, actualValue: String)
    
    /// Internal execution error
    case executionError(underlying: Error)
    
    public var errorDescription: String? {
        switch self {
        case .notFound(let uri):
            return "Resource not found: \(uri)"
        case .templateMismatch(let template, let uri):
            return "URI '\(uri)' does not match template '\(template)'"
        case .missingParameter(let name):
            return "Missing required parameter: \(name)"
        case .typeMismatch(let parameter, let expectedType, let actualValue):
            return "Parameter '\(parameter)' type mismatch: expected \(expectedType), got '\(actualValue)'"
        case .executionError(let error):
            return "Resource execution error: \(error.localizedDescription)"
        }
    }
} 