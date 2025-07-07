import Foundation
import AnyCodable
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

    /// ID token from OAuth response (if any).
    public var idToken: String?

    /// User information fetched from the OAuth provider (if any).
    public var userInfo: UserInfo?

    /// Convenience accessors for common user info fields
    public var userID: String? { userInfo?.sub }
    public var email: String? { userInfo?.email }
    public var name: String? { userInfo?.name }
    public var givenName: String? { userInfo?.givenName }
    public var familyName: String? { userInfo?.familyName }
    public var picture: String? { userInfo?.picture }
    public var emailVerified: Bool? { userInfo?.emailVerified }

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


extension Session {
    /// Send a progress notification to the client associated with this session.
    /// - Parameters:
    ///   - progressToken: The token identifying the operation progress belongs to.
    ///   - progress: Current progress value.
    ///   - total: Optional total value if known.
    ///   - message: Optional human-readable progress message.
    public func sendProgressNotification(progressToken: AnyCodable,
                                         progress: Double,
                                         total: Double? = nil,
                                         message: String? = nil) async {
        var params: [String: AnyCodable] = [
            "progressToken": progressToken,
            "progress": AnyCodable(progress)
        ]
        if let total = total { params["total"] = AnyCodable(total) }
        if let message = message { params["message"] = AnyCodable(message) }

        let notification = JSONRPCMessage.notification(method: "notifications/progress",
                                                       params: params)
        do {
            try await transport?.send(notification)
        } catch {
            // Intentionally ignore send errors in tests
        }
    }
}
