import Foundation

/// Protocol defining the requirements for an MCP resource
public protocol MCPResource: Codable, Sendable {
    /// The URI of the resource
    var uri: URL { get }
    
    /// The name of the resource
    var name: String { get }
    
    /// The description of the resource
    var description: String { get }
    
    /// The MIME type of the resource
    var mimeType: String { get }
}
