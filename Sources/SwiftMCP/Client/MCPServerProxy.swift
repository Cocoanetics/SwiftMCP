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
        return .integer(requestIdSequence)
    }

    /// Correlates the SSE / streamable-HTTP path's outbound requests to their
    /// replies, by id — JSONFoundation's ``RequestCorrelator``, held in this actor.
    /// (The stdio / TCP / in-process paths correlate inside their `JSONRPCPeer`.)
    internal let responses = RequestCorrelator<JSONRPCID, JSONRPCMessage>()
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
    /// The server's human-friendly display title, if it advertised one (2025-06-18+).
    public internal(set) var serverTitle: String?
    /// The server's website URL, if it advertised one (2025-06-18+).
    public internal(set) var serverWebsiteUrl: URL?
    /// The server's display icons (2025-06-18+); empty when none were advertised.
    public internal(set) var serverIcons: [Icon] = []
    public internal(set) var serverCapabilities: ServerCapabilities?

    /// The protocol revision negotiated with the server during `initialize`
    /// (the value the server echoed back, which may be older than the `latest`
    /// the client proposed). `nil` until the handshake completes. The client
    /// honors this when acting on the connection — notably the
    /// `MCP-Protocol-Version` header it sends on subsequent streamable-HTTP
    /// requests.
    public internal(set) var negotiatedProtocolVersion: String?

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

    /// The shared JSON-RPC correlator driving the line-based transports
    /// (stdio / TCP / in-process), in pull mode over ``lineTransport``. The
    /// SSE / streamable-HTTP path keeps its own request-scoped flow (it needs
    /// cross-channel typed termination errors the peer doesn't model), but its
    /// id→reply bookkeeping now also rides ``RequestCorrelator`` (``responses``).
    internal var linePeer: JSONRPCPeer?
    /// The line transport the ``linePeer`` owns; retained so it can be closed on
    /// `disconnect`.
    internal var lineTransport: (any JSONRPCMessageTransport)?
    /// The in-process server runner for `.stdioHandles`, retained so its loopback
    /// server end keeps running and can be torn down on `disconnect`.
    internal var inProcessLoopback: InProcessServerLoopback?
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
        case .integer(let value):
            return String(value)
        case .string(let value):
            return value
        }
    }
}
#endif
