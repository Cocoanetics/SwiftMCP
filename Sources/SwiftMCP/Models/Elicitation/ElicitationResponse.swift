import Foundation
@preconcurrency import AnyCodable

/// Represents the response to an elicitation request.
public struct ElicitationCreateResponse: Codable, Sendable {
    /// The action taken by the user in response to the elicitation request.
    public enum Action: String, Codable, Sendable {
        /// User explicitly approved and submitted with data
        case accept
        /// User explicitly declined the request
        case decline
        /// User dismissed without making an explicit choice
        case cancel
    }
    
    /// The action taken by the user.
    public let action: Action
    
    /// The submitted data matching the requested schema (present for accept action).
    /// This field contains the user's responses when action is "accept".
    public let content: [String: AnyCodable]?
    
    public init(action: Action, content: [String: AnyCodable]? = nil) {
        self.action = action
        self.content = content
    }
} 