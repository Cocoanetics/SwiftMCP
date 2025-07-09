import Foundation

/// Represents a message in a sampling conversation.
public struct SamplingMessage: Codable, Sendable {
    /// The role of the message sender.
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }
    
    /// The content of the message.
    public let content: SamplingContent
    
    /// The role of the message sender.
    public let role: Role
    
    public init(role: Role, content: SamplingContent) {
        self.role = role
        self.content = content
    }
}

/// Represents the content of a sampling message.
public struct SamplingContent: Codable, Sendable {
    /// The type of content.
    public enum ContentType: String, Codable, Sendable {
        case text
        case image
        case audio
    }
    
    /// The type of content.
    public let type: ContentType
    
    /// Text content (for text type).
    public let text: String?
    
    /// Binary data (for image/audio types).
    public let data: Data?
    
    /// MIME type (for image/audio types).
    public let mimeType: String?
    
    /// Creates a text content message.
    public init(text: String) {
        self.type = .text
        self.text = text
        self.data = nil
        self.mimeType = nil
    }
    
    /// Creates an image content message.
    public init(imageData: Data, mimeType: String) {
        self.type = .image
        self.text = nil
        self.data = imageData
        self.mimeType = mimeType
    }
    
    /// Creates an audio content message.
    public init(audioData: Data, mimeType: String) {
        self.type = .audio
        self.text = nil
        self.data = audioData
        self.mimeType = mimeType
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(ContentType.self, forKey: .type)
        self.text = try container.decodeIfPresent(String.self, forKey: .text)
        self.mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        
        // Handle base64 encoded data
        if let base64String = try container.decodeIfPresent(String.self, forKey: .data) {
            guard let data = Data(base64Encoded: base64String) else {
                throw DecodingError.dataCorruptedError(forKey: .data, in: container, debugDescription: "Invalid base64 data")
            }
            self.data = data
        } else {
            self.data = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        
        // Encode data as base64 string
        if let data = data {
            let base64String = data.base64EncodedString()
            try container.encode(base64String, forKey: .data)
        }
    }
} 