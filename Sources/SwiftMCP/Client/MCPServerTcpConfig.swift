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

    /// Timeout for Bonjour discovery and connection establishment.
    public let timeout: TimeInterval

    /// Prefer IPv4 when establishing the TCP connection.
    public let preferIPv4: Bool

    /// Create a Bonjour-based configuration.
    public init(
        serviceName: String? = nil,
        domain: String = "local.",
        serviceType: String = "_mcp._tcp",
        timeout: TimeInterval = 10,
        preferIPv4: Bool = true
    ) {
        self.endpoint = .bonjour(serviceName: serviceName, domain: domain)
        self.serviceType = serviceType
        self.timeout = timeout
        self.preferIPv4 = preferIPv4
    }

    /// Create a direct host/port configuration.
    public init(
        host: String,
        port: UInt16,
        serviceType: String = "_mcp._tcp",
        timeout: TimeInterval = 10,
        preferIPv4: Bool = true
    ) {
        self.endpoint = .direct(host: host, port: port)
        self.serviceType = serviceType
        self.timeout = timeout
        self.preferIPv4 = preferIPv4
    }
}
