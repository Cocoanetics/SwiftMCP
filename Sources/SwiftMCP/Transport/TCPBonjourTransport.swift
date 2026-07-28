#if Server
import Foundation
import Logging
import ServiceLifecycle

#if canImport(Network)
import Network

/// A TCP transport that advertises via Bonjour and exchanges newline-delimited JSON-RPC.
///
/// `TCPBonjourTransport` works in two modes:
///
/// - **Server-coupled:** construct it with `init(server:)` and run it directly
///   (e.g. inside your own `ServiceGroup`). It dispatches through the server
///   itself, and derives its advertised name and TXT record from the server.
/// - **Decoupled:** construct it with `init(instanceName:)` (no server) and hand
///   it to ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``, which
///   connects an ``MCPDispatcher`` via ``connect(to:)``. Each accepted TCP
///   connection binds its own session and routes inbound lines through `handle`.
///
/// The service type is always ``MCPBonjour/serviceType``. Identity lives in the
/// Bonjour instance name, and how far that name reaches is ``DiscoveryScope``.
public final class TCPBonjourTransport: Transport, MCPTransport, Service, @unchecked Sendable {
    /// DNS-SD service type for MCP over TCP. Always `_mcp._tcp`.
    public static let serviceType = MCPBonjour.serviceType

    /// The MCP server exposed in the server-coupled mode. `nil` in the decoupled
    /// mode, where the ``MCPDispatcher`` connected by `serve(over:)` owns dispatch.
    public let server: MCPServer?

    /// The dispatcher `serve` connects in the decoupled mode. `nil` until
    /// ``connect(to:)`` is called (and in the server-coupled mode). Read by the
    /// receive loop in `TCPBonjourTransport+Connections.swift`.
    internal var dispatcher: (any MCPDispatcher)?
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")

    /// The **base** instance name. The advertised name is derived from it by the
    /// scope — see ``advertisedInstanceName``. When nil, `server.serverName` is used.
    public let instanceName: String?

    /// How far this service is advertised, and what it binds to.
    public let scope: DiscoveryScope

    public let preferIPv4: Bool
    public internal(set) var port: UInt16?

    /// The instance name mDNSResponder actually registered.
    ///
    /// Normally equal to ``advertisedInstanceName``, but mDNS resolves conflicts by
    /// renaming — a second `Post (oliver)` becomes `Post (oliver) (2)`. Once identity
    /// lives in the instance name, a server that cannot report the name it actually
    /// published cannot be diagnosed, so this is read back from the registration.
    /// `nil` until the listener is ready.
    public internal(set) var resolvedInstanceName: String?

    /// Resolves the sibling HTTP endpoint, or nil when there is none yet.
    ///
    /// A closure rather than a stored string because a sibling `HTTPSSETransport`
    /// may be configured with port `0`: its real port only exists after it binds,
    /// which is after `serve(over:)` wires the transports together. Snapshotting
    /// the value there would permanently omit `http` for every ephemeral server.
    internal var httpEndpointProvider: (@Sendable () -> String?)?

    /// `port/path` at which the same server is also reachable over HTTP/SSE.
    ///
    /// Populated by ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` from
    /// the sibling transports it was given — serving one server over several
    /// transports at once is normal, and a client should not have to guess where
    /// the other one is. Not app-supplied.
    public var httpEndpoint: String? { httpEndpointProvider?() }

    /// Server name and version for the TXT record in the decoupled mode, where
    /// there is no `server` to read them from.
    internal var declaredServerName: String?
    internal var declaredServerVersion: String?

    internal let queue = DispatchQueue(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")
    internal let state = TransportState()
    internal lazy var sessionManager = SessionManager(transport: self)

    /// Maximum delay between retry attempts (in seconds).
    internal static let maxRetryDelay: UInt64 = 60

    // MARK: - Init

    /// Creates a server-coupled transport.
    ///
    /// - Parameters:
    ///   - server: The MCP server to expose. Supplies the default instance name
    ///     and the TXT record.
    ///   - instanceName: Base instance name. Defaults to `server.serverName`.
    ///     The scope derives the advertised name from it.
    ///   - scope: How far to advertise. Defaults to ``DiscoveryScope/localUser``.
    ///   - port: TCP port, or `nil` to pick automatically.
    ///   - preferIPv4: Prefer IPv4 when binding. Defaults to `true`.
    public init(
        server: MCPServer,
        instanceName: String? = nil,
        scope: DiscoveryScope = .localUser,
        port: UInt16? = nil,
        preferIPv4: Bool = true
    ) {
        self.server = server
        self.instanceName = instanceName
        self.scope = scope
        self.port = port
        self.preferIPv4 = preferIPv4
        self.declaredServerName = nil
        self.declaredServerVersion = nil
        // Force the lazy manager on the constructing thread: instance `lazy` is a
        // non-atomic check-then-store, and its first touch would otherwise be a
        // per-connection task — concurrent first connections could double-create it.
        _ = sessionManager
    }

    /// Creates a decoupled transport with no server.
    ///
    /// Pass the transport to ``MCPServer/serve(over:gracefulShutdownSignals:logger:)``,
    /// which connects an ``MCPDispatcher`` and runs it.
    ///
    /// There is no server to read TXT metadata from here, so pass `serverName` and
    /// `serverVersion` if you want them advertised — otherwise the TXT record
    /// carries only the instance name.
    ///
    /// - Parameters:
    ///   - instanceName: Base instance name. The scope derives the advertised name.
    ///   - scope: How far to advertise. Defaults to ``DiscoveryScope/localUser``.
    ///   - serverName: Server name for the TXT record. Defaults to `instanceName`.
    ///   - serverVersion: Server version for the TXT record.
    ///   - port: TCP port, or `nil` to pick automatically.
    ///   - preferIPv4: Prefer IPv4 when binding. Defaults to `true`.
    public init(
        instanceName: String,
        scope: DiscoveryScope = .localUser,
        serverName: String? = nil,
        serverVersion: String? = nil,
        port: UInt16? = nil,
        preferIPv4: Bool = true
    ) {
        self.server = nil
        self.instanceName = instanceName
        self.scope = scope
        self.port = port
        self.preferIPv4 = preferIPv4
        self.declaredServerName = serverName
        self.declaredServerVersion = serverVersion
        // See the server-coupled initializer.
        _ = sessionManager
    }

    deinit {
        // A transport released without `stop()` must not orphan its listener:
        // an orphaned `NWListener` keeps accepting (and thus leaking) connections
        // with no owner left to ever cancel them. `TransportState` is an actor,
        // so hop onto it; the task retains the actor until the sweep completes.
        let state = self.state
        Task { await state.stop() }
    }

    /// Connects the dispatcher `serve` routes inbound TCP lines through.
    ///
    /// In the decoupled mode this is also where the server becomes known, so a
    /// TXT record that could not be built at construction time is completed here.
    public func connect(to dispatcher: any MCPDispatcher) {
        self.dispatcher = dispatcher
    }
}
#else

/// Stub implementation for platforms without Network framework.
public final class TCPBonjourTransport: Transport, MCPTransport, Service, @unchecked Sendable {
    /// DNS-SD service type for MCP over TCP. Always `_mcp._tcp`.
    public static let serviceType = MCPBonjour.serviceType

    public let server: MCPServer?
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")

    public let instanceName: String?
    public let scope: DiscoveryScope
    public let preferIPv4: Bool
    public private(set) var port: UInt16?
    public private(set) var resolvedInstanceName: String?
    internal var httpEndpointProvider: (@Sendable () -> String?)?
    public var httpEndpoint: String? { httpEndpointProvider?() }

    internal var declaredServerName: String?
    internal var declaredServerVersion: String?

    public init(
        server: MCPServer,
        instanceName: String? = nil,
        scope: DiscoveryScope = .localUser,
        port: UInt16? = nil,
        preferIPv4: Bool = true
    ) {
        self.server = server
        self.instanceName = instanceName
        self.scope = scope
        self.port = port
        self.preferIPv4 = preferIPv4
        self.declaredServerName = nil
        self.declaredServerVersion = nil
    }

    /// Decoupled initializer. Building/running fails at runtime on platforms
    /// without the Network framework.
    public init(
        instanceName: String,
        scope: DiscoveryScope = .localUser,
        serverName: String? = nil,
        serverVersion: String? = nil,
        port: UInt16? = nil,
        preferIPv4: Bool = true
    ) {
        self.server = nil
        self.instanceName = instanceName
        self.scope = scope
        self.port = port
        self.preferIPv4 = preferIPv4
        self.declaredServerName = serverName
        self.declaredServerVersion = serverVersion
    }

    /// No-op on platforms without the Network framework; the transport cannot run.
    public func connect(to dispatcher: any MCPDispatcher) {}

    public func start() async throws {
        throw TransportError.bindingFailed("TCP+Bonjour transport requires the Network framework.")
    }

    public func run() async throws {
        try await start()
    }

    public func stop() async throws {
    }

    public func send(_ data: Data) async throws {
    }
}
#endif
#endif
