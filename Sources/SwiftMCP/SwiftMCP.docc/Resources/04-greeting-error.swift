/*
A custom error type for handling validation errors in the MCP server.
*/
import Foundation

enum GreetingError: LocalizedError {
    case nameTooShort

    var errorDescription: String? {
        switch self {
            case .nameTooShort:
                return "Name must be at least 2 characters long"
        }
    }
} 