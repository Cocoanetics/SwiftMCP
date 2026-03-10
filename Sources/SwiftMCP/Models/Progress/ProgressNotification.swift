import Foundation

/// Represents a progress notification as defined in the MCP protocol specification.
public struct ProgressNotification: Codable, Sendable {
    /// The token identifying the operation the progress update belongs to.
    public let progressToken: AnyCodable

    /// The current progress value.
    public let progress: Double

    /// An optional total value if known.
    public let total: Double?

    /// An optional human-readable progress message.
    public let message: String?

    /// Creates a new progress notification.
    /// - Parameters:
    ///   - progressToken: The token identifying the operation the progress update belongs to.
    ///   - progress: The current progress value.
    ///   - total: An optional total value if known.
    ///   - message: An optional human-readable progress message.
    public init(progressToken: AnyCodable,
                progress: Double,
                total: Double? = nil,
                message: String? = nil) {
        self.progressToken = progressToken
        self.progress = progress
        self.total = total
        self.message = message
    }
}
