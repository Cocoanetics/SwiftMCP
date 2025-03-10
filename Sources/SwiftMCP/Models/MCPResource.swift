import Foundation

/// Protocol defining the requirements for an MCP resource
public protocol MCPResource: Codable {
    /// The URI of the resource
    var uri: URL { get }
    
    /// The name of the resource
    var name: String { get }
    
    /// The description of the resource
    var description: String { get }
    
    /// The MIME type of the resource
    var mimeType: String { get }
}


/// Errors that can occur when working with MCPResources
public enum MCPResourceError: Error, CustomStringConvertible {
    /// The URI string is invalid
    case invalidURI(String)
    
    /// A description of the error
    public var description: String {
        switch self {
        case .invalidURI(let uriString):
            return "Invalid URI: \(uriString)"
        }
    }
} 
