//
//  MCPBonjour.swift
//  SwiftMCP
//
//  DNS-SD naming for MCP over TCP.
//
//  There is exactly one service type, and it is a constant. It identifies the
//  *protocol*, not any particular server — a server does not have a service type,
//  MCP does. Deriving a type per server (the previous `forServer`) put identity in
//  the wrong field: it made the type skew across versions, it could not fit a
//  server name into the 15-character RFC 6335 limit without truncating distinct
//  names to the same value, and it made discovery impossible, since you had to
//  already know a server's name to build the type to look for it.
//
//  Identity lives in the Bonjour *instance* name instead, which is a single DNS
//  label of up to 63 bytes of readable UTF-8 — see ``DiscoveryScope``.
//
//  This file is deliberately not trait-gated: both the client and the server
//  refer to the same constant, and they must not be able to disagree.
//

import Foundation

/// DNS-SD naming for MCP over TCP.
public enum MCPBonjour {
    /// The DNS-SD service type for MCP over TCP (RFC 6763 §7).
    ///
    /// SwiftMCP owns this type and no other. Apps that advertise non-MCP
    /// endpoints — a pairing handshake, a REST API, a custom protocol — own
    /// those service types themselves; this constant does not govern them.
    public static let serviceType = "_mcp._tcp"

    /// The service type in the trailing-dot form `NetService` expects.
    public static let registrationType = serviceType + "."
}
