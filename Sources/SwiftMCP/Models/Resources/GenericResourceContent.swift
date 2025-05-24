import Foundation

/// Generic implementation of MCPResourceContent for simple text resources
public struct GenericResourceContent: MCPResourceContent {
    public let uri: URL
    public let mimeType: String?
    public let text: String?
    public let blob: Data?
    
    public init(uri: URL, mimeType: String? = nil, text: String? = nil, blob: Data? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }
} 