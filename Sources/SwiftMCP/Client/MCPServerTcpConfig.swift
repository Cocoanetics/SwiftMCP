#if Client
import Foundation

/// Configuration for connecting to an MCP server via TCP.
public struct MCPServerTcpConfig: Sendable {
    /// Defines how the TCP endpoint should be resolved.
    public enum Endpoint: Sendable {
        /// Discover a service via Bonjour.
        case bonjour(serviceName: String? = nil, domain: String = "local.")

        /// Connect directly to a host and port.
        case direct(host: String, port: UInt16)
    }

    /// The endpoint resolution strategy.
    public let endpoint: Endpoint

    /// The Bonjour service type to browse for.
    public let serviceType: String

    /// The legacy server-derived service type to browse during migration.
    internal let fallbackServiceType: String?
    internal let usesDefaultServiceType: Bool

    internal var bonjourServiceTypes: [String] {
        if let fallbackServiceType {
            return [serviceType, fallbackServiceType]
        }
        return [serviceType]
    }

    /// Timeout for Bonjour discovery and connection establishment.
    public let timeout: TimeInterval

    /// Prefer IPv4 when establishing the TCP connection.
    public let preferIPv4: Bool

    /// Create a Bonjour-based configuration.
    ///
    /// When `serviceType` is nil, the base MCP service type (`_mcp._tcp`) is used.
    /// A `serviceName` filters discovered services by their Bonjour instance name
    /// and also enables browsing the legacy server-derived type during migration.
    public init(
        serviceName: String? = nil,
        domain: String = "local.",
        serviceType: String? = nil,
        timeout: TimeInterval = 10,
        preferIPv4: Bool = true
    ) {
        self.endpoint = .bonjour(serviceName: serviceName, domain: domain)
        if let serviceType {
            self.serviceType = serviceType
            self.fallbackServiceType = nil
            self.usesDefaultServiceType = false
        } else {
            self.serviceType = MCPBonjourServiceType.base
            self.fallbackServiceType = serviceName.map(MCPBonjourServiceType.forServer)
            self.usesDefaultServiceType = true
        }
        self.timeout = timeout
        self.preferIPv4 = preferIPv4
    }

    /// Create a direct host/port configuration.
    public init(
        host: String,
        port: UInt16,
        serviceType: String = MCPBonjourServiceType.base,
        timeout: TimeInterval = 10,
        preferIPv4: Bool = true
    ) {
        self.endpoint = .direct(host: host, port: port)
        self.serviceType = serviceType
        self.fallbackServiceType = nil
        self.usesDefaultServiceType = false
        self.timeout = timeout
        self.preferIPv4 = preferIPv4
    }
}
#endif
