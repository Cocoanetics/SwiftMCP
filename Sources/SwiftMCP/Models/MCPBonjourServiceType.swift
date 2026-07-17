//
//  MCPBonjourServiceType.swift
//  SwiftMCP
//
//  DNS-SD / Bonjour service-type naming for MCP over TCP. These helpers live in
//  the always-on core (not behind the `Server` trait) so the client-side
//  `MCPServerTcpConfig` can derive default service types without linking the
//  `TCPBonjourTransport` server transport.
//

import Foundation

/// DNS-SD service-type naming for MCP over TCP.
public enum MCPBonjourServiceType {
    /// Base DNS-SD service type for MCP over TCP.
    public static let base = "_mcp._tcp"

    /// Returns a valid server-specific service type derived from the server name.
    ///
    /// Invalid characters are replaced with hyphens and the service label is
    /// limited to the DNS-SD maximum of 15 characters.
    public static func forServer(_ serverName: String) -> String {
        let components = serverName.lowercased().unicodeScalars.split {
            !((97...122).contains($0.value) || (48...57).contains($0.value))
        }
        let sanitized = components.map(String.init).joined(separator: "-")
        let prefix = String(sanitized.prefix(11)).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let name = prefix.isEmpty ? "server" : String(prefix)
        return "_\(name)-mcp._tcp"
    }
}
