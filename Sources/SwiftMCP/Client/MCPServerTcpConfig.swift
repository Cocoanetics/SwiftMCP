#if Client
import Foundation

/// Configuration for connecting to an MCP server via TCP.
public struct MCPServerTcpConfig: Sendable {
    /// Defines how the TCP endpoint should be resolved.
    public enum Endpoint: Sendable {
        /// Discover a service via Bonjour by its **base** instance name.
        ///
        /// The name is the same base the server was given; ``DiscoveryScope``
        /// derives the advertised form on both sides. Pass `nil` to browse for
        /// every MCP service in scope and let the caller choose.
        case bonjour(instanceName: String? = nil)

        /// Connect directly to a host and port, with no discovery.
        ///
        /// The escape hatch when discovery fails or is unavailable. Worth exposing
        /// from any CLI that relies on Bonjour, so a discovery regression is
        /// recoverable without a rebuild.
        case direct(host: String, port: UInt16)
    }

    /// The endpoint resolution strategy.
    public let endpoint: Endpoint

    /// How far to look. Must match the scope the server advertises at.
    public let scope: DiscoveryScope

    /// The DNS-SD service type browsed for. Always ``MCPBonjour/serviceType``.
    public var serviceType: String { MCPBonjour.serviceType }

    /// Timeout for Bonjour discovery and connection establishment.
    public let timeout: TimeInterval

    /// Prefer IPv4 when establishing the TCP connection.
    public let preferIPv4: Bool

    /// Create a Bonjour-based configuration.
    ///
    /// - Parameters:
    ///   - instanceName: The server's **base** instance name, or `nil` to browse
    ///     for all MCP services in scope.
    ///   - scope: Must match the server's scope. Defaults to ``DiscoveryScope/localUser``.
    ///   - timeout: Discovery and connection timeout.
    ///   - preferIPv4: Prefer IPv4 when connecting.
    public init(
        instanceName: String? = nil,
        scope: DiscoveryScope = .localUser,
        timeout: TimeInterval = 10,
        preferIPv4: Bool = true
    ) {
        self.endpoint = .bonjour(instanceName: instanceName)
        self.scope = scope
        self.timeout = timeout
        self.preferIPv4 = preferIPv4
    }

    /// Create a direct host/port configuration.
    public init(
        host: String,
        port: UInt16,
        timeout: TimeInterval = 10,
        preferIPv4: Bool = true
    ) {
        self.endpoint = .direct(host: host, port: port)
        self.scope = .localUser
        self.timeout = timeout
        self.preferIPv4 = preferIPv4
    }

    /// The instance name to match against browse results.
    ///
    /// `nil` only for a nameless browse. Every scope derives symmetrically, so
    /// this is the same string the server asked mDNS to register.
    internal var derivedInstanceName: String? {
        guard case .bonjour(let base) = endpoint, let base else { return nil }
        return scope.instanceName(for: base)
    }

    /// The base name as configured, before the scope derives from it.
    internal var baseInstanceName: String? {
        guard case .bonjour(let base) = endpoint else { return nil }
        return base
    }
}
#endif
