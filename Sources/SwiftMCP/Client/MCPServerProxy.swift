#if Client
import SwiftCross
import Logging

/// A proxy for interacting with an MCP server over stdio, TCP, or SSE.
public final actor MCPServerProxy {
    internal struct NotificationHandlerBox: Sendable {
        let payloadTypeDescription: String
        let handle: @Sendable (
            MCPServerProxy,
            JSONRPCMessage.JSONRPCNotificationData
        ) async throws -> Void
    }

    internal struct ToolsListResult: Decodable, Sendable {
        let tools: [MCPTool]
    }

    internal struct ResourcesListResult: Decodable, Sendable {
        let resources: [SimpleResource]
    }

    internal struct ResourceTemplatesListResult: Decodable, Sendable {
        let resourceTemplates: [SimpleResourceTemplate]
    }

    internal struct ResourceReadResult: Decodable, Sendable {
        let contents: [GenericResourceContent]
    }

    internal struct PromptsListResult: Decodable, Sendable {
        let prompts: [Prompt]
    }

    internal struct ResourceUpdatedParams: Decodable, Sendable {
        let uri: String
    }

    internal enum NotificationMethod {
        static let log = "notifications/message"
        static let progress = "notifications/progress"
        static let toolsListChanged = "notifications/tools/list_changed"
        static let resourcesListChanged = "notifications/resources/list_changed"
        static let promptsListChanged = "notifications/prompts/list_changed"
        static let resourceUpdated = "notifications/resources/updated"
    }

    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.MCPServerProxy")

    /// The configuration for the MCP server.
    public let config: MCPServerConfig

    /// Optional Bonjour service name to prefer during discovery.
    public var service: String?

    /// Specifies whether the list of tools from the server should be cached.
    public let cacheToolsList: Bool

    /// Base metadata included in _meta for ALL requests (e.g., accessToken).
    public var meta: JSONDictionary = [:]

    internal var cachedTools: [MCPTool]?
    private var requestIdSequence: Int = 0

    internal func nextRequestID() -> JSONRPCID {
        defer { requestIdSequence += 1 }
        return .int(requestIdSequence)
    }

    internal var responseTasks: [JSONRPCID: CheckedContinuation<JSONRPCMessage, Error>] = [:]
    internal var streamFailure: Error?
    internal var isDisconnecting = false

    public internal(set) var endpointURL: URL?
    public internal(set) var sessionID: String?
    internal var streamTask: Task<Void, Error>?
    /// Identifies the currently-active stream. Bumped whenever a stream is
    /// retired (reconnect / disconnect) so a late `handleStreamTermination`
    /// from a now-stale stream task is ignored instead of failing the requests
    /// of the connection that replaced it.
    internal var streamGeneration: Int = 0

    public internal(set) var serverName: String?
    public internal(set) var serverVersion: String?
    public internal(set) var serverDescription: String?
    public internal(set) var serverCapabilities: ServerCapabilities?

    internal var notificationHandlers: [String: NotificationHandlerBox] = [:]

    /// Optional handler for log notifications from the server.
    public var logNotificationHandler: (any MCPServerProxyLogNotificationHandling)? {
        didSet {
            updateLogNotificationRegistration()
        }
    }

    /// Optional handler for progress notifications from the server.
    public var progressNotificationHandler: (any MCPServerProxyProgressNotificationHandling)? {
        didSet {
            updateProgressNotificationRegistration()
        }
    }

    /// Optional handler for resource-updated notifications from the server.
    /// Installing this handler enables the client to receive `notifications/resources/updated`
    /// for subscribed resources. The client automatically advertises subscription support
    /// during initialization when this handler is set before `connect()`.
    public var resourceNotificationHandler: (any MCPServerProxyResourceNotificationHandling)? {
        didSet {
            updateResourceNotificationRegistration()
        }
    }

    /// Optional handler for tools list-changed notifications.
    /// When set, the client advertises support during initialization
    /// (if set before `connect()`).
    public var toolsListChangedHandler: (any MCPServerProxyToolsListChangedHandling)? {
        didSet {
            updateToolsListChangedRegistration()
        }
    }

    /// Optional handler for resources list-changed notifications.
    /// When set, the client advertises support during initialization
    /// (if set before `connect()`).
    public var resourcesListChangedHandler: (any MCPServerProxyResourcesListChangedHandling)? {
        didSet {
            updateResourcesListChangedRegistration()
        }
    }

    /// Optional handler for prompts list-changed notifications.
    /// When set, the client advertises support during initialization
    /// (if set before `connect()`).
    public var promptsListChangedHandler: (any MCPServerProxyPromptsListChangedHandling)? {
        didSet {
            updatePromptsListChangedRegistration()
        }
    }

    internal var lineConnection: (any StdioConnection)?
    internal var endpointContinuation: CheckedContinuation<URL, Error>?

    public init(config: MCPServerConfig, cacheToolsList: Bool = false) {
        self.config = config
        self.service = nil
        self.cacheToolsList = cacheToolsList
    }
}

extension JSONRPCID {
    internal var stringValue: String {
        switch self {
        case .int(let value):
            return String(value)
        case .string(let value):
            return value
        }
    }
}
#endif
