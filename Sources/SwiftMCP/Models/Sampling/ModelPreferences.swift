import Foundation

/// Represents model preferences for sampling requests.
@Schema
public struct ModelPreferences: Codable, Sendable {
    /// Model hints for preference matching.
    @Schema
    public struct ModelHint: Codable, Sendable {
        /// The name or partial name of the model to prefer.
        public let name: String
        
        public init(name: String) {
            self.name = name
        }
    }
    
    /// Optional hints for model selection.
    public let hints: [ModelHint]?
    
    /// Priority for cost optimization (0-1, higher = more important).
    public let costPriority: Double?
    
    /// Priority for speed optimization (0-1, higher = more important).
    public let speedPriority: Double?
    
    /// Priority for intelligence/capability (0-1, higher = more important).
    public let intelligencePriority: Double?
    
    public init(
        hints: [ModelHint]? = nil,
        costPriority: Double? = nil,
        speedPriority: Double? = nil,
        intelligencePriority: Double? = nil
    ) {
        self.hints = hints
        self.costPriority = costPriority
        self.speedPriority = speedPriority
        self.intelligencePriority = intelligencePriority
    }
} 
