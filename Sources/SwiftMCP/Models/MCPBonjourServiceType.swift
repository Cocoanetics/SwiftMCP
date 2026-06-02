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

    /// Returns a server-specific service type derived from the server name,
    /// e.g. `"Post"` → `"_post-mcp._tcp"`. This prevents Bonjour collisions
    /// between unrelated MCP servers on the same network.
    public static func forServer(_ serverName: String) -> String {
        "_\(serverName.lowercased())-mcp._tcp"
    }
}
