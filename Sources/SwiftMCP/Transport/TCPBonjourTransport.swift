import Foundation
import Logging

#if canImport(Network)
import Network

/// A TCP transport that advertises via Bonjour and exchanges newline-delimited JSON-RPC.
public final class TCPBonjourTransport: Transport, @unchecked Sendable {
    /// Base DNS-SD service type for MCP over TCP.
    public static let serviceType = "_mcp._tcp"

    /// Returns a server-specific service type derived from the server name,
    /// e.g. `"Post"` → `"_post-mcp._tcp"`.  This prevents Bonjour collisions
    /// between unrelated MCP servers on the same network.
    public static func serviceType(for serverName: String) -> String {
        "_\(serverName.lowercased())-mcp._tcp"
    }

    public let server: MCPServer
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")

    /// Optional override for the advertised Bonjour service name.
    /// When nil, the transport uses `server.serverName`.
    public let serviceName: String?
    public let serviceType: String
    public let serviceDomain: String
    public let acceptLocalOnly: Bool
    public let preferIPv4: Bool
    public internal(set) var port: UInt16?

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
            return generation
        }

        /// Replace the current listener with a new one during retry recovery.
        /// Returns the new generation token, or nil if the transport is stopped.
        func replaceListener(_ newListener: NWListener, expectedGeneration: UInt64) -> UInt64? {
            guard isRunning, generation == expectedGeneration else {
                return nil
            }
            listener?.cancel()
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

    public init(
        server: MCPServer,
        serviceName: String? = nil,
        serviceType: String? = nil,
        serviceDomain: String = "local.",
        port: UInt16? = nil,
        acceptLocalOnly: Bool = true,
        preferIPv4: Bool = true
    ) {
        self.server = server
        self.serviceName = serviceName
        // Default to a server-specific service type derived from the server name
        self.serviceType = serviceType ?? TCPBonjourTransport.serviceType(for: server.serverName)
        self.serviceDomain = serviceDomain
        self.port = port
        self.acceptLocalOnly = acceptLocalOnly
        self.preferIPv4 = preferIPv4
    }

    public convenience init(server: MCPServer) {
        self.init(
            server: server,
            serviceName: nil,
            serviceType: nil,
            serviceDomain: "local.",
            port: nil,
            acceptLocalOnly: true,
            preferIPv4: true
        )
    }
}
#else
import Foundation
import Logging

/// Stub implementation for platforms without Network framework.
public final class TCPBonjourTransport: Transport, @unchecked Sendable {
    /// Base DNS-SD service type for MCP over TCP.
    public static let serviceType = "_mcp._tcp"

    /// Returns a server-specific service type derived from the server name,
    /// e.g. `"Post"` → `"_post-mcp._tcp"`.
    public static func serviceType(for serverName: String) -> String {
        "_\(serverName.lowercased())-mcp._tcp"
    }

    public let server: MCPServer
    public let logger = Logger(label: "com.cocoanetics.SwiftMCP.TCPBonjourTransport")

    /// Optional override for the advertised Bonjour service name.
    /// When nil, the transport uses `server.serverName`.
    public let serviceName: String?
    public let serviceType: String
    public let serviceDomain: String
    public let acceptLocalOnly: Bool
    public let preferIPv4: Bool
    public private(set) var port: UInt16?

    public init(
        server: MCPServer,
        serviceName: String? = nil,
        serviceType: String? = nil,
        serviceDomain: String = "local.",
        port: UInt16? = nil,
        acceptLocalOnly: Bool = true,
        preferIPv4: Bool = true
    ) {
        self.server = server
        self.serviceName = serviceName
        self.serviceType = serviceType ?? TCPBonjourTransport.serviceType(for: server.serverName)
        self.serviceDomain = serviceDomain
        self.port = port
        self.acceptLocalOnly = acceptLocalOnly
        self.preferIPv4 = preferIPv4
    }

    public convenience init(server: MCPServer) {
        self.init(
            server: server,
            serviceName: nil,
            serviceType: nil,
            serviceDomain: "local.",
            port: nil,
            acceptLocalOnly: true,
            preferIPv4: true
        )
    }

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
