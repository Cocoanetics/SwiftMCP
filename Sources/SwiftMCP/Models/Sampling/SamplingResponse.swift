import Foundation

/// Represents a sampling response with the generated message.
public struct SamplingCreateMessageResponse: Codable, Sendable {
    /// The role of the generated message.
    public let role: SamplingMessage.Role
    
    /// The content of the generated message.
    public let content: SamplingContent
    
    /// The model that was used for generation.
    public let model: String?
    
    /// The reason why generation stopped.
    public let stopReason: String?
    
    public init(
        role: SamplingMessage.Role,
        content: SamplingContent,
        model: String? = nil,
        stopReason: String? = nil
    ) {
        self.role = role
        self.content = content
        self.model = model
        self.stopReason = stopReason
    }
} 