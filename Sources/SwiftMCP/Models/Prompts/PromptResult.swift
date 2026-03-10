import Foundation

/// The result returned by `prompts/get`.
public struct PromptResult: Codable, Sendable {
    public let description: String?
    public let messages: [PromptMessage]

    public init(description: String? = nil, messages: [PromptMessage]) {
        self.description = description
        self.messages = messages
    }
}
