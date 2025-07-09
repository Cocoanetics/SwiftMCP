import Foundation
import AnyCodable

/// Represents the context of a single JSON-RPC message.
///
/// A context tracks the message identifier, method name and optional
/// metadata like a progress token. It is stored in task local storage so
/// it can be accessed from anywhere while handling the message.
public final class RequestContext: @unchecked Sendable {
    /// Additional metadata sent in the `_meta` field of a request.
    public struct Meta: @unchecked Sendable {
        /// Optional progress token for sending progress notifications.
        public let progressToken: AnyCodable?

        init?(dictionary: [String: Any]) {
            if let token = dictionary["progressToken"] {
                self.progressToken = AnyCodable(token)
            } else {
                self.progressToken = nil
            }
        }
    }

    /// The identifier of the JSON-RPC message.
    public let id: JSONRPCID?
    /// The method of the JSON-RPC message if applicable.
    public let method: String?
    /// Optional metadata for the message.
    public let meta: Meta?

    /// Creates a new request context for the given message.
    public init(message: JSONRPCMessage) {
        switch message {
        case .request(let data):
            id = data.id
            method = data.method
            if let params = data.params,
               let dict = params["_meta"]?.value as? [String: Any] {
                meta = Meta(dictionary: dict)
            } else {
                meta = nil
            }
        case .notification(let data):
            id = nil
            method = data.method
            if let params = data.params,
               let dict = params["_meta"]?.value as? [String: Any] {
                meta = Meta(dictionary: dict)
            } else {
                meta = nil
            }
        case .response(let data):
            id = data.id
            method = nil
            meta = nil
        case .errorResponse(let data):
            id = data.id
            method = nil
            meta = nil
        }
    }

    @TaskLocal
    private static var taskContext: RequestContext?

    /// Accessor for the current context stored in task local storage.
    public static var current: RequestContext! { taskContext }

    /// Runs `operation` with this context bound to `RequestContext.current`.
    public func work<T>(_ operation: (RequestContext) async throws -> T) async rethrows -> T {
        try await Self.$taskContext.withValue(self) {
            try await operation(self)
        }
    }

    /// Send a progress notification if a progress token was provided.
    public func reportProgress(_ progress: Double, total: Double? = nil, message: String? = nil) async {
        guard let progressToken = meta?.progressToken else { return }
        if let session = Session.current {
            await session.sendProgressNotification(progressToken: progressToken,
                                                  progress: progress,
                                                  total: total,
                                                  message: message)
        }
    }
}
