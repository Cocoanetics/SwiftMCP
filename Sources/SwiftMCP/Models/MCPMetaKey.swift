//
//  MCPMetaKey.swift
//  SwiftMCP
//
//  The reserved `_meta` keys defined by the Model Context Protocol. From the
//  modern (`2026-07-28`+) revision, requests carry their protocol version,
//  client identity, capabilities and log level here instead of negotiating them
//  once via an `initialize` handshake.
//

import Foundation

/// Well-known keys used inside a request's `_meta` object.
///
/// The modern, stateless transport conveys per-request identity through these
/// keys; see ``RequestContext/effectiveProtocolVersion`` and friends for the
/// resolution that prefers them over legacy session state.
public enum MCPMetaKey {
    /// The protocol revision this request uses, e.g. `"2026-07-28"`.
    public static let protocolVersion = "io.modelcontextprotocol/protocolVersion"

    /// The client software identity (`Implementation`: name, version, …).
    public static let clientInfo = "io.modelcontextprotocol/clientInfo"

    /// The client's declared capabilities (`ClientCapabilities`).
    public static let clientCapabilities = "io.modelcontextprotocol/clientCapabilities"

    /// The log level requested for this single request (modern per-request logging).
    public static let logLevel = "io.modelcontextprotocol/logLevel"
}
