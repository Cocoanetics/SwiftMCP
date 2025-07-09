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

    /// The minimum log level for this session (default: .info)
    public var minimumLogLevel: LogLevel = .info

    /// Client capabilities received during initialization (if any).
    public var clientCapabilities: ClientCapabilities?

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

    /// Send a log message notification to the client associated with this session, filtered by minimumLogLevel.
    /// - Parameter message: The log message to send
    public func sendLogNotification(_ message: LogMessage) async {
        guard message.level.isAtLeast(self.minimumLogLevel) else { return }
        var params: [String: AnyCodable] = [
            "level": AnyCodable(message.level.rawValue),
            "data": message.data
        ]
        if let logger = message.logger { params["logger"] = AnyCodable(logger) }

        let notification = JSONRPCMessage.notification(method: "notifications/message",
                                                       params: params)
        do {
            try await transport?.send(notification)
        } catch {
            // Intentionally ignore send errors in tests
        }
    }

    /// Send a roots/list request to the client and return the roots.
    /// - Returns: The list of roots available to the client
    /// - Throws: An error if the client doesn't support roots or the request fails
    public func listRoots() async throws -> RootsList {
        // Check if client supports roots
        guard clientCapabilities?.roots != nil else {
            throw RootsError.clientDoesNotSupportRoots
        }

        let request = JSONRPCMessage.request(id: .string(UUID().uuidString), method: "roots/list")
        
        do {
            try await transport?.send(request)
            // Note: In a real implementation, we would need to wait for the response
            // For now, we'll return an empty list as this is a server-side implementation
            // and the actual response handling would need to be implemented in the transport layer
            return RootsList(roots: [])
        } catch {
            throw RootsError.requestFailed(error)
        }
    }

    /// Send a notification that the roots list has changed.
    /// This should be called by clients when their available roots change.
    public func sendRootsListChangedNotification() async {
        let notification = JSONRPCMessage.notification(method: "notifications/roots/list_changed")
        do {
            try await transport?.send(notification)
        } catch {
            // Intentionally ignore send errors in tests
        }
    }
}

/// Errors related to roots functionality.
public enum RootsError: Error, LocalizedError {
    case clientDoesNotSupportRoots
    case requestFailed(Error)
    
    public var errorDescription: String? {
        switch self {
        case .clientDoesNotSupportRoots:
            return "Client does not support roots capability"
        case .requestFailed(let error):
            return "Roots request failed: \(error.localizedDescription)"
        }
    }
}
