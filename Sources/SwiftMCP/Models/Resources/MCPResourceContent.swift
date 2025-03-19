import Foundation

/// Protocol defining the requirements for MCP resource content
public protocol MCPResourceContent: Codable {
    /// The URI of the resource
    var uri: URL { get }
    
    /// The MIME type of the resource (optional)
    var mimeType: String? { get }
    
    /// The text content of the resource (if it's a text resource)
    var text: String? { get }
    
    /// The binary content of the resource (if it's a binary resource)
    var blob: Data? { get }
}
