import Foundation
import NIO

/// Represents a connection session.
///
/// A session tracks the client identifier and the transport that should be used
/// for sending responses back to this client.
public actor Session {
    /// Unique identifier of the session/client.
    public let id: UUID

    /// The transport associated with this session. Weak to avoid retain cycles.
    public weak var transport: (any Transport)?

    /// The SSE channel associated with this session, if any.
    public var channel: Channel?

    /// Continuation for the SSE response stream.
    /// When set, `sendSSE` yields formatted event data into this stream
    /// instead of writing directly to the NIO channel.
    var sseContinuation: AsyncStream<Data>.Continuation?

    // MARK: - Request/Response Tracking
    /// Continuations for sent requests, to match up responses
    internal var responseTasks: [String: CheckedContinuation<JSONRPCMessage, Error>] = [:]

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
    
    /// Client info received during initialization (if any).
    public var clientInfo: Implementation?

    /// The protocol version negotiated during initialize.
    public var negotiatedProtocolVersion: String?

    /// Whether this session has received an MCP initialize request.
    public var hasReceivedInitializeRequest: Bool = false

    /// URIs that this session has subscribed to for resource-updated notifications.
    internal var subscribedResourceURIs: Set<String> = []

    /// Timestamp of the most recent activity associated with this session.
    public var lastActivityAt: Date = Date()

    /// Optional expiry deadline used for retained sessions after disconnect.
    public var expiresAt: Date?

    /// Creates a new session.
    /// - Parameters:
    ///   - id: The unique session identifier.
    public init(id: UUID, channel: Channel? = nil) {
        self.id = id
        self.channel = channel
    }

    @TaskLocal
    internal static var taskSession: Session?

    @TaskLocal
    internal static var taskStreamContext: OutboundStreamContext?

    /// Accessor for the current session stored in task local storage.
    public static var current: Session! {
        taskSession
    }

    internal static var currentStreamContext: OutboundStreamContext? {
        taskStreamContext
    }

    /// Runs `operation` with this session bound to `Session.current`.
    public func work<T: Sendable>(_ operation: @Sendable (Session) async throws -> T) async rethrows -> T {
        try await Self.$taskSession.withValue(self) {
            try await operation(self)
        }
    }

    /// Runs `operation` with this session and an outbound stream context bound.
    internal func work<T: Sendable>(
        onStream streamContext: OutboundStreamContext?,
        _ operation: @Sendable (Session) async throws -> T
    ) async rethrows -> T {
        try await Self.$taskSession.withValue(self) {
            try await Self.$taskStreamContext.withValue(streamContext) {
                try await operation(self)
            }
        }
    }

    /// Indicates whether this session currently has an active SSE connection.
    public var hasActiveConnection: Bool {
        sseContinuation != nil && (channel?.isActive ?? false)
    }

    /// Send an SSE message through the session's stream continuation.
    /// - Parameter message: The message to send.
    func sendSSE(_ message: SSEMessage) async {
        guard let transport = transport as? HTTPSSETransport else { return }
        await transport.routeSSEMessage(
            message,
            sessionID: id,
            preferredStreamID: Self.currentStreamContext?.streamID
        )
    }

    /// Set the SSE stream continuation for this session.
    func setSSEContinuation(_ continuation: AsyncStream<Data>.Continuation?) {
        self.sseContinuation = continuation
    }

    // MARK: - Convenience Mutators

    /// Update the access token stored for this session.
    /// - Parameter token: The new access token value.
    public func setAccessToken(_ token: String?) {
        self.accessToken = token
    }

    /// Update the expiry date for the stored access token.
    /// - Parameter date: The new expiry date.
    public func setAccessTokenExpiry(_ date: Date?) {
        self.accessTokenExpiry = date
    }

    /// Update the associated transport (weak reference) for this session.
    public func setTransport(_ transport: (any Transport)?) {
        self.transport = transport
    }

    /// Update the channel associated with this session.
    public func setChannel(_ channel: Channel?) {
        self.channel = channel
    }

    /// Update the userInfo stored for this session.
    public func setUserInfo(_ info: UserInfo?) {
        self.userInfo = info
    }

    /// Update the minimum log level for this session.
    public func setMinimumLogLevel(_ level: LogLevel) {
        self.minimumLogLevel = level
    }

    /// Update the ID token stored for this session.
    public func setIDToken(_ token: String?) {
        self.idToken = token
    }
    
    /// Update the client capabilities stored for this session.
    public func setClientCapabilities(_ capabilities: ClientCapabilities?) {
        self.clientCapabilities = capabilities
    }
    
    /// Update the client info stored for this session.
    public func setClientInfo(_ info: Implementation?) {
        self.clientInfo = info
    }

    /// Update the negotiated protocol version for this session.
    public func setNegotiatedProtocolVersion(_ version: String?) {
        self.negotiatedProtocolVersion = version
    }

    /// Mark the session as having received an MCP initialize request.
    public func markInitializeRequestReceived() {
        hasReceivedInitializeRequest = true
    }

    /// Record session activity and clear any pending expiry.
    public func touchActivity() {
        lastActivityAt = Date()
        expiresAt = nil
    }

    /// Update the expiry deadline used for retained sessions.
    public func setExpiresAt(_ date: Date?) {
        expiresAt = date
    }

    /// Sends a JSON-RPC message to the client and waits for the response.
    /// - Parameter message: The JSON-RPC message to send
    /// - Returns: The response message from the client
    /// - Throws: An error if the message fails to send or if no response is received
    @discardableResult public func send(_ message: JSONRPCMessage) async throws -> JSONRPCMessage {
        guard let messageId = message.id else {
            preconditionFailure("Message requires an id")
        }
        
        // Extract the string ID for tracking
        let id: String
        switch messageId {
        case .int(let intId):
            id = String(intId)
        case .string(let stringId):
            id = stringId
        }
        
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<JSONRPCMessage, Error>) in
            responseTasks[id] = continuation
            
            // Send the message via the transport, activating the session context
            Task {
                do {
                    try await self.work { _ in
                        try await transport?.send(message)
                    }
                } catch {
                    if responseTasks[id] != nil {
                        responseTasks.removeValue(forKey: id)
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    /// Handles an incoming JSON-RPC response by matching it with a waiting continuation.
    /// - Parameter response: The response message to handle
    internal func handleResponse(_ response: JSONRPCMessage) {
        guard let messageId = response.id else { return }
        
        let id: String
        switch messageId {
        case .int(let intId):
            id = String(intId)
        case .string(let stringId):
            id = stringId
        }
        
        if let continuation = responseTasks[id] {
            responseTasks.removeValue(forKey: id)
            continuation.resume(returning: response)
        }
    }
    
    /// Sends a JSON-RPC request with an auto-generated ID and waits for the response.
    /// - Parameters:
    ///   - method: The method name to call
    ///   - params: Optional parameters for the request
    /// - Returns: The response message from the client
    /// - Throws: An error if the request fails or if no response is received
    public func request(method: String, params: JSONDictionary? = nil) async throws -> JSONRPCMessage {
        let message = JSONRPCMessage.request(id: .string(UUID().uuidString), method: method, params: params)
        return try await send(message)
    }

    public func request<T: Encodable & Sendable>(method: String, params value: T) async throws -> JSONRPCMessage {
        try await request(method: method, params: JSONDictionary(encoding: value))
    }
    
    /// Cancels all waiting continuations when the session is being removed.
    /// This prevents continuation leaks when sessions are disconnected.
    internal func cancelAllWaitingTasks() {
        let tasks = responseTasks
        responseTasks.removeAll()
        
        for (_, continuation) in tasks {
            continuation.resume(throwing: CancellationError())
        }
    }
}
