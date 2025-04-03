import Foundation

/// Protocol defining the requirements for an MCP resource template
public protocol MCPResourceTemplate: Codable, Sendable {
    /// The URI of the resource
    var uriTemplate: URL { get }
    
    /// The name of the resource
    var name: String { get }
    
    /// The description of the resource
    var description: String { get }
    
    /// The MIME type of the resource
    var mimeType: String { get }
}
