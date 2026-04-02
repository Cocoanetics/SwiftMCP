import Foundation

public enum OAuthConfigurationError: Error, LocalizedError {
    case invalidURL(String)
    case fileNotFound(String)
    case invalidJSON(String)
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL(let details):
            return "Invalid URL in OAuth configuration: \(details)"
        case .fileNotFound(let path):
            return "OAuth configuration file not found: \(path)"
        case .invalidJSON(let details):
            return "Invalid JSON in OAuth configuration: \(details)"
        }
    }
}
