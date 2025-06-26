import Foundation
import NIO

/// Represents a connection session.
///
/// A session tracks the client identifier and the transport that should be used
/// for sending responses back to this client.
public final class Session: @unchecked Sendable {
    /// Unique identifier of the session/client.
    public let id: UUID

    /// The transport associated with this session. Weak to avoid retain cycles.
    public weak var transport: (any Transport)?

    /// The SSE channel associated with this session, if any.
    public var channel: Channel?

    // MARK: - OAuth token (light-weight session storage)
    /// Access-token issued for this session (if any).
    public var accessToken: String?

    /// Absolute expiry date for `accessToken`.
    public var accessTokenExpiry: Date?

    /// Creates a new session.
    /// - Parameters:
    ///   - id: The unique session identifier.
    public init(id: UUID, channel: Channel? = nil) {
        self.id = id
        self.channel = channel
    }

    @TaskLocal
    private static var taskSession: Session?

    /// Accessor for the current session stored in task local storage.
    public static var current: Session! {
        taskSession
    }

    /// Runs `operation` with this session bound to `Session.current`.
    public func work<T>(_ operation: @Sendable (Session) async throws -> T) async rethrows -> T {
        try await Self.$taskSession.withValue(self) {
            try await operation(self)
        }
    }

    /// Indicates whether this session currently has an active SSE channel.
    public var hasActiveConnection: Bool {
        channel?.isActive ?? false
    }

    /// Send an SSE message through the session's channel if available.
    /// - Parameter message: The message to send.
    func sendSSE(_ message: SSEMessage) {
        guard let channel, channel.isActive else { return }
        channel.sendSSE(message)
    }
}

