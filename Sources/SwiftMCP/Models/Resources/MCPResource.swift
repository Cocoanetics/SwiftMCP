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

/// Simple implementation of MCPResource
public struct SimpleResource: MCPResource {
    public let uri: URL
    public let name: String
    public let description: String
    public let mimeType: String

    public init(uri: URL, name: String, description: String? = nil, mimeType: String? = nil) {
        self.uri = uri
        self.name = name
        self.description = description ?? ""
        self.mimeType = mimeType ?? "text/plain"
    }
}
