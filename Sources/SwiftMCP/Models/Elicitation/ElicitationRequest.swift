import Foundation

/// Represents an elicitation request to gather user information.
public struct ElicitationCreateRequest: Codable, Sendable {
    /// A human-readable message explaining what information is being requested.
    public let message: String
    
    /// The JSON schema defining the structure of the expected response.
    /// This is limited to flat objects with primitive properties only.
    public let requestedSchema: JSONSchema
    
    public init(message: String, requestedSchema: JSONSchema) {
        self.message = message
        self.requestedSchema = requestedSchema
    }
} 