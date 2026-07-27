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

    /// `port/path` at which the same server is also reachable over HTTP/SSE.
    ///
    /// Populated by ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` from
    /// the sibling transports it was given — serving one server over several
    /// transports at once is normal, and a client should not have to guess where
    /// the other one is. Not app-supplied.
    public internal(set) var httpEndpoint: String?

    /// Server name and version for the TXT record in the decoupled mode, where
    /// there is no `server` to read them from.
    internal var declaredServerName: String?
    internal var declaredServerVersion: String?

    internal let queue = DispatchQueue(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")
    internal let state = TransportState()
    internal lazy var sessionManager = SessionManager(transport: self)

    /// Maximum delay between retry attempts (in seconds).
    internal static let maxRetryDelay: UInt64 = 60

    // MARK: - Transport State

    internal actor TransportState {
        private(set) var isRunning: Bool = false
        private(set) var generation: UInt64 = 0
        private var listener: NWListener?
        private var connections: [UUID: NWConnection] = [:]
        private var runContinuation: CheckedContinuation<Void, Never>?
        private var retryTask: Task<Void, Never>?
        private var localRegistration: LocalOnlyRegistration?
        private(set) var retryAttempt: Int = 0

        func running() -> Bool {
            isRunning
        }

        /// Start a new listener generation.
        /// Returns the generation token for this listener.
        @discardableResult
        func start(listener: NWListener) -> UInt64 {
            generation += 1
            self.listener = listener
            isRunning = true
            retryAttempt = 0
            cancelRetryTask()
            localRegistration?.stop()
            localRegistration = nil
            return generation
        }

        /// Replace the current listener with a new one during retry recovery.
        /// Returns the new generation token, or nil if the transport is stopped.
        func replaceListener(_ newListener: NWListener, expectedGeneration: UInt64) -> UInt64? {
            guard isRunning, generation == expectedGeneration else {
                return nil
            }
            listener?.cancel()
            localRegistration?.stop()
            localRegistration = nil
            generation += 1
            self.listener = newListener
            return generation
        }

        func stop() {
            isRunning = false
            generation += 1  // invalidate any in-flight retry / state callbacks
            cancelRetryTask()
            retryAttempt = 0
            listener?.cancel()
            listener = nil
            localRegistration?.stop()
            localRegistration = nil
            for connection in connections.values {
                connection.cancel()
            }
            connections.removeAll()
            if let continuation = runContinuation {
                runContinuation = nil
                continuation.resume()
            }
        }

        func waitUntilStopped() async {
            guard isRunning else { return }
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                runContinuation = continuation
            }
        }

        /// Called when the listener reaches `.ready`.
        /// Resets backoff, clears any pending retry, and returns the bound port (if available).
        func listenerReady(generation listenerGen: UInt64) -> UInt16? {
            guard listenerGen == generation, isRunning else { return nil }
            retryAttempt = 0
            cancelRetryTask()
            return listener?.port?.rawValue
        }

        func setLocalRegistration(
            _ registration: LocalOnlyRegistration,
            generation listenerGen: UInt64
        ) -> Bool {
            guard listenerGen == generation, isRunning else { return false }
            localRegistration?.stop()
            localRegistration = registration
            return true
        }

        func removeLocalRegistration(generation listenerGen: UInt64) {
            guard listenerGen == generation else { return }
            localRegistration?.stop()
            localRegistration = nil
        }

        /// Called when the listener fails with a retryable error.
        /// Increments the backoff attempt and returns the delay in seconds,
        /// or nil if the transport is stopped or the generation is stale.
        func listenerFailed(generation listenerGen: UInt64) -> UInt64? {
            guard listenerGen == generation, isRunning else { return nil }
            retryAttempt += 1
            let delay = min(UInt64(1) << UInt64(min(retryAttempt - 1, 5)), TCPBonjourTransport.maxRetryDelay)
            return delay
        }

        /// Store a retry task. Cancels any existing one first.
        func setRetryTask(_ task: Task<Void, Never>) {
            cancelRetryTask()
            retryTask = task
        }

        private func cancelRetryTask() {
            retryTask?.cancel()
            retryTask = nil
        }

        func addConnection(id: UUID, connection: NWConnection) {
            connections[id] = connection
        }

        func removeConnection(id: UUID) {
            connections.removeValue(forKey: id)
        }

        func connection(for id: UUID) -> NWConnection? {
            connections[id]
        }
    }

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
    public internal(set) var httpEndpoint: String?

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

extension TCPBonjourTransport {
    /// The base name before the scope decorates it.
    internal var baseInstanceName: String {
        instanceName ?? server?.serverName ?? declaredServerName ?? "MCP"
    }

    /// The instance name this transport asks mDNSResponder to register.
    ///
    /// Derived from ``baseInstanceName`` by the scope. For the local scopes a
    /// client on the same machine derives the identical string from the same base
    /// name, which is what lets a named lookup succeed without any lookup table.
    public var advertisedInstanceName: String {
        scope.instanceName(for: baseInstanceName)
    }

    /// Records what ``MCPServer/serve(over:gracefulShutdownSignals:logger:)`` knows
    /// and the transport cannot: the server's identity when this transport was built
    /// decoupled, and where a sibling transport serves the same server over HTTP.
    ///
    /// Called before the listener starts, so the TXT record is complete when the
    /// service is first published.
    internal func advertise(server: any MCPServer, httpEndpoint: String?) {
        if declaredServerName == nil { declaredServerName = server.serverName }
        if declaredServerVersion == nil { declaredServerVersion = server.serverVersion }
        if let httpEndpoint { self.httpEndpoint = httpEndpoint }
    }

    /// The TXT record to advertise.
    internal var txtRecord: BonjourTXTRecord {
        BonjourTXTRecord(
            serverName: server?.serverName ?? declaredServerName ?? baseInstanceName,
            serverVersion: server?.serverVersion ?? declaredServerVersion,
            protocolVersion: MCPProtocolVersion.latest,
            // A pid is only meaningful to a client on the same machine.
            processID: scope.isLocalOnly ? ProcessIdentity.processID : nil,  // meaningful only same-machine
            httpEndpoint: httpEndpoint
        )
    }
}
#endif
