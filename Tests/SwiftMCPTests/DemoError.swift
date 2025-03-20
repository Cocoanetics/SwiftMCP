import Foundation

/// Custom errors for the demo app
public enum DemoError: LocalizedError {
    /// When a greeting name is too short
    case nameTooShort(name: String)
    
    /// When a greeting name contains invalid characters
    case invalidName(name: String)
    
    /// When the greeting service is temporarily unavailable
    case serviceUnavailable
    
    public var errorDescription: String? {
        switch self {
        case .nameTooShort(let name):
            return "Name '\(name)' is too short. Names must be at least 2 characters long."
        case .invalidName(let name):
            return "Name '\(name)' contains invalid characters. Only letters and spaces are allowed."
        case .serviceUnavailable:
            return "The greeting service is temporarily unavailable. Please try again later."
        }
    }
} 