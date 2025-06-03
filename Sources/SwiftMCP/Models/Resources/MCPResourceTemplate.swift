import Foundation

/// Protocol defining the requirements for an MCP resource template
public protocol MCPResourceTemplate: Codable, Sendable {
    /// The URI template of the resource
    var uriTemplate: String { get }

    /// The name of the resource
    var name: String { get }

    /// The description of the resource
    var description: String? { get }

    /// The MIME type of the resource
    var mimeType: String? { get }
}
