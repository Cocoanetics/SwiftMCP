import Foundation

/// Represents a sampling request to create a message.
public struct SamplingCreateMessageRequest: Codable, Sendable {
    /// The messages in the conversation.
    public let messages: [SamplingMessage]
    
    /// Optional model preferences for the request.
    public let modelPreferences: ModelPreferences?
    
    /// Optional system prompt to guide the model.
    public let systemPrompt: String?
    
    /// Maximum number of tokens to generate.
    public let maxTokens: Int?
    
    public init(
        messages: [SamplingMessage],
        modelPreferences: ModelPreferences? = nil,
        systemPrompt: String? = nil,
        maxTokens: Int? = nil
    ) {
        self.messages = messages
        self.modelPreferences = modelPreferences
        self.systemPrompt = systemPrompt
        self.maxTokens = maxTokens
    }
} 