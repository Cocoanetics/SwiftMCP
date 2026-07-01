#if Server
import Foundation
import HTTPTypes
import Logging
import ServiceLifecycle

/**
 A transport that exposes an HTTP server with Server-Sent Events (SSE) and JSON-RPC endpoints.

 It provides:

 - Server-Sent Events (SSE) for real-time updates
 - JSON-RPC over HTTP for command processing
 - Optional OpenAPI endpoints for API documentation
 - Configurable authorization
 - Keep-alive mechanisms

 The transport is the NIO-free *engine*: it owns routing, sessions, and SSE, and
 conforms to ``MCPHTTPEngine``. The socket, HTTP framing, and read/write loops live
 in a pluggable adapter behind that seam (``NIOHTTPServerAdapter`` for 1.x); the
 engine links no swift-nio. See ``MCPHTTPEngine`` and `Transport/Adapters/`.
 */
public final class HTTPSSETransport: Transport, MCPTransport, Service, MCPHTTPEngine, @unchecked Sendable {
    /// The MCP server instance that this transport exposes in the server-coupled
    /// mode. `nil` in the decoupled mode, where the ``MCPDispatcher`` connected by
    /// ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` owns dispatch.
    public let server: MCPServer?

    /// The dispatcher `serve` connects in the decoupled mode. `nil` until
    /// ``connect(to:)`` is called (and in the server-coupled mode). Read by the
    /// route handlers in `MCPRoutes.swift` / `LegacySSERoutes.swift`.
    internal var dispatcher: (any MCPDispatcher)?

    /// The server in the server-coupled mode. Routes that introspect the server
    /// (OpenAPI) are only registered when `server != nil`, so this is only reached
    /// in that mode.
    internal var coupledServer: MCPServer {
        guard let server else {
            preconditionFailure("server-coupled route reached without a server")
        }
        return server
    }

    /// The hostname or IP address on which the HTTP server listens.
    public let host: String

    /// The port number on which the HTTP server listens.
    /// If initialized with `0`, the system will select an available port
    /// when the server starts. The actual bound port is then available
    /// via this property after ``start()`` completes.
    public internal(set) var port: Int

    /// Logger for logging transport events and errors.
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.HTTPSSETransport")

    /// The socket adapter created in ``start()``. NIO (or any future framework)
    /// lives entirely behind this; the engine never touches it directly.
    private var adapter: NIOHTTPServerAdapter?

    public var streamRetentionInterval: TimeInterval = 5 * 60
    internal lazy var sessionManager = SessionManager(
        transport: self,
        retentionInterval: streamRetentionInterval
    )
    internal var keepAliveTimer: DispatchSourceTimer?

    /// The HTTP router that dispatches incoming requests to route handlers.
    internal lazy var router: Router = buildRouter()

    /// Custom routes registered by the user via `addRoute`.
    internal var customRoutes: [HTTPRoute] = []

    /// Flag to determine whether to serve OpenAPI endpoints.
    public var serveOpenAPI: Bool = false

    /// Maximum allowed HTTP message size in bytes (defaults to 4 MB).
    public var maxMessageSize: Int = 4 * 1024 * 1024

    /// Result of an authorization check.
    public enum AuthorizationResult: Sendable {
        case authorized
        case unauthorized(String)
        case jweNotSupported(String)
    }

    /// A function type that handles authorization of requests.
    public typealias AuthorizationHandler = @Sendable (String?) -> AuthorizationResult

    /// Authorization handler for bearer tokens.
    public var authorizationHandler: AuthorizationHandler = { _ in return .authorized }

    /// Optional OAuth configuration. When set, incoming bearer tokens are
    /// validated using the provided settings and `.well-known` endpoints are
    /// served with the corresponding metadata.
    public var oauthConfiguration: OAuthConfiguration?

    /// Defines the available keep-alive modes for maintaining connections.
    public enum KeepAliveMode: Sendable {
        case none
        case sse
        case ping
    }

    /// The current keep-alive mode for the transport.
    public var keepAliveMode: KeepAliveMode = .ping {
        didSet {
            if oldValue != keepAliveMode {
                if keepAliveMode == .none {
                    stopKeepAliveTimer()
                } else {
                    startKeepAliveTimer()
                }
            }
        }
    }

    /// The number of active SSE channels currently connected to the server.
    var sseChannelCount: Int {
        get async { await sessionManager.channelCount }
    }

    // MARK: - Initialization

    public init(server: MCPServer, host: String = ProcessInfo.processInfo.hostName, port: Int = 8080) {
        self.server = server
        self.host = host
        self.port = port
    }

    public convenience init(server: MCPServer) {
        self.init(server: server, host: ProcessInfo.processInfo.hostName, port: 8080)
    }

    /// Initializes a decoupled HTTP+SSE transport with no server.
    ///
    /// Pass the transport to ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``,
    /// which connects an ``MCPDispatcher`` and runs it. Each POST binds its
    /// `Mcp-Session-Id` session and its per-request SSE stream, then calls
    /// `handle`. OpenAPI endpoints are unavailable in this mode (they introspect
    /// the server's tools, which the decoupled transport does not hold).
    public init(host: String = ProcessInfo.processInfo.hostName, port: Int = 8080) {
        self.server = nil
        self.host = host
        self.port = port
    }

    /// Connects the dispatcher `serve` routes inbound POSTs through.
    public func connect(to dispatcher: any MCPDispatcher) {
        self.dispatcher = dispatcher
    }

    // MARK: - Server Lifecycle

    public func start() async throws {
        let adapter = NIOHTTPServerAdapter(engine: self, logger: logger)
        self.adapter = adapter
        // Binding resolves an ephemeral `0` to the actual port.
        self.port = try await adapter.start()
        startKeepAliveTimer()
    }

    /// Runs the transport and blocks until it is stopped.
    ///
    /// When executed inside a `ServiceGroup`, a graceful shutdown signal (e.g.
    /// `SIGINT`/`SIGTERM`) stops the adapter via ``stop()`` so this method returns
    /// and the group can drain. When called standalone, it returns once the
    /// listener closes.
    public func run() async throws {
        try await start()
        try await withGracefulShutdownHandler {
            try await adapter?.waitUntilClosed()
        } onGracefulShutdown: { [weak self] in
            // `onGracefulShutdown` is synchronous; bridge to the async `stop()`.
            Task { [weak self] in try? await self?.stop() }
        }
    }

    public func stop() async throws {
        logger.info("Stopping server...")
        stopKeepAliveTimer()
        await sessionManager.removeAllSessions()
        try await adapter?.shutdown()
        logger.info("Server stopped")
    }

    // MARK: - Transport

    /// Send raw data to the client associated with the current `Session`.
    public func send(_ data: Data) async throws {
        precondition(Session.current != nil, "Attempted to send without an active session")
        let session = Session.current!

        let string = String(data: data, encoding: .utf8) ?? ""
        let message = SSEMessage(data: string)
        let routed = await sessionManager.routeSSEMessage(
            message,
            sessionID: session.id,
            preferredStreamID: Session.currentStreamContext?.streamID
        )
        if !routed {
            throw TransportError.bindingFailed("No routable SSE stream for session \(session.id)")
        }
    }

    // MARK: - MCPHTTPEngine

    public var configuredHost: String { host }
    public var configuredPort: Int { port }

    /// The maximum request-body size for the route matching `head`.
    public func maxBodySize(for head: HTTPRequest) -> Int {
        let (path, _) = Self.parseURI(head.path ?? "/")
        if let match = router.match(method: head.method, path: path),
           let perRoute = match.route.maxBodySize {
            return perRoute
        }
        return maxMessageSize
    }

    /// Route and dispatch one request, returning the response the adapter writes.
    public func handle(head: HTTPRequest, bodyStream: AsyncStream<Data>) async -> EngineResponse {
        let uri = head.path ?? "/"
        let (path, queryParams) = Self.parseURI(uri)

        guard let routeMatch = router.match(method: head.method, path: path) else {
            return EngineResponse(status: .notFound, headerFields: [:], body: .buffered(nil))
        }

        let request = HTTPRouteRequest<AsyncStream<Data>>(
            method: head.method, uri: uri, path: path,
            headerFields: Self.requestHeaderFields(from: head), body: bodyStream,
            pathParams: routeMatch.pathParams, queryParams: queryParams
        )

        do {
            let response = try await routeMatch.route.handler(self, request)
            return Self.engineResponse(from: response)
        } catch {
            logger.error("Route handler error: \(error)")
            return EngineResponse(
                status: .internalServerError,
                headerFields: [:],
                body: .buffered(Data("Internal Server Error".utf8))
            )
        }
    }

    /// Bind a live connection to an SSE stream the engine just opened.
    public func registerConnection(
        _ connection: any SSEConnection,
        for registration: SSERegistration
    ) async -> SSEConnectionToken? {
        guard let token = await sessionManager.register(
            connection: connection,
            sessionID: registration.sessionID,
            streamID: registration.streamID
        ) else {
            return nil
        }
        let count = await sessionManager.channelCount
        logger.info("New SSE channel registered (total: \(count))")
        return SSEConnectionToken(streamID: registration.streamID, connectionToken: token)
    }

    /// Mark an SSE stream disconnected when the adapter reports its socket closed.
    public func connectionDisconnected(_ token: SSEConnectionToken) async {
        await sessionManager.markStreamDisconnected(
            streamID: token.streamID,
            connectionToken: token.connectionToken
        )
        let count = await sessionManager.channelCount
        logger.info("SSE channel removed (remaining: \(count))")
    }

    // MARK: - Request helpers (NIO-free, shared by every adapter)

    /// The request's header fields, re-exposing the `Host` header that the HTTP/1
    /// codec lifts into the `:authority` pseudo-header, so routes that read
    /// `header("Host")` keep working.
    static func requestHeaderFields(from request: HTTPRequest) -> HTTPFields {
        var fields = request.headerFields
        // `HTTPField.Name.host` is unavailable (HTTP/2 maps Host to `:authority`),
        // so reconstruct the literal `Host` field name to re-expose it.
        let hostName = HTTPField.Name("Host")!
        if let authority = request.authority, fields[hostName] == nil {
            fields[hostName] = authority
        }
        return fields
    }

    /// Split a URI into its path and decoded query parameters.
    static func parseURI(_ uri: String) -> (path: String, queryParams: [(String, String)]) {
        guard let questionMark = uri.firstIndex(of: "?") else {
            return (uri, [])
        }
        let path = String(uri[..<questionMark])
        let queryString = String(uri[uri.index(after: questionMark)...])
        let queryParams = queryString.split(separator: "&").compactMap { pair -> (String, String)? in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard let key = parts.first.flatMap({ String($0).removingPercentEncoding }) else { return nil }
            let value = parts.count > 1 ? (String(parts[1]).removingPercentEncoding ?? "") : ""
            return (key, value)
        }
        return (path, queryParams)
    }

    private static func engineResponse(from response: RouteResponse) -> EngineResponse {
        if let stream = response.bodyStream {
            let registration = response.streamInfo.map {
                SSERegistration(sessionID: $0.sessionID, streamID: $0.streamID)
            }
            return EngineResponse(
                status: response.status,
                headerFields: response.headerFields,
                body: .sse(stream: stream, registration: registration)
            )
        }
        return EngineResponse(
            status: response.status,
            headerFields: response.headerFields,
            body: .buffered(response.body)
        )
    }
}
#endif
