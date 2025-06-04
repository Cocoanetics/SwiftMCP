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
}
