import Foundation

public struct PromptMessage: Codable, Sendable {
    public enum Role: String, Codable, Sendable {
        case user
        case assistant
    }

    public struct Content: Codable, Sendable {
        public enum ContentType: String, Codable, Sendable {
            case text
            case image
            case audio
            case resource
        }

        public var type: ContentType
        public var text: String?
        public var data: Data?
        public var mimeType: String?
        public var resource: GenericResourceContent?

        public init(text: String) {
            self.type = .text
            self.text = text
        }

        public init(imageData: Data, mimeType: String) {
            self.type = .image
            self.data = imageData
            self.mimeType = mimeType
        }

        public init(audioData: Data, mimeType: String) {
            self.type = .audio
            self.data = audioData
            self.mimeType = mimeType
        }

        public init(resource: GenericResourceContent) {
            self.type = .resource
            self.resource = resource
        }
    }

    public var role: Role
    public var content: Content

    public init(role: Role, content: Content) {
        self.role = role
        self.content = content
    }

    /// Converts any result to an array of PromptMessage, similar to fastmcp Message logic
    public static func fromResult(_ result: Any) -> [PromptMessage] {
        if let message = result as? PromptMessage {
            return [message]
        } else if let messages = result as? [PromptMessage] {
            return messages
        } else if let str = result as? String {
            return [PromptMessage(role: .user, content: .init(text: str))]
        } else if let encodable = result as? Encodable {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(AnyEncodable(encodable)),
               let json = String(data: data, encoding: .utf8) {
                return [PromptMessage(role: .user, content: .init(text: json))]
            }
        }
        // Fallback: use String(describing:)
        let text = String(describing: result)
        return [PromptMessage(role: .user, content: .init(text: text))]
    }
}

/// Helper to encode any Encodable type
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}
