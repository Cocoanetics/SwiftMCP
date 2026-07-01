//
//  MCPProtocolVersion.swift
//  SwiftMCP
//
//  The MCP protocol versions understood by this package. These constants live
//  in the always-on core (not behind the `Server` trait) because both the
//  server-runtime initialize handshake and the client (`MCPServerProxy`) need
//  to negotiate the protocol version without linking the HTTP transport.
//

import Foundation

/// Model Context Protocol revisions supported by SwiftMCP.
public enum MCPProtocolVersion {
    /// The most recent protocol revision advertised during initialization.
    public static let latest = "2025-11-25"

    /// Intermediate revision still accepted over the HTTP transport.
    public static let intermediateHTTP = "2025-06-18"

    /// Oldest revision still accepted over the HTTP transport.
    public static let fallbackHTTP = "2025-03-26"

    /// The full set of protocol revisions this package can negotiate.
    public static let supported: Set<String> = [
        latest,
        intermediateHTTP,
        fallbackHTTP
    ]

    /// The negotiable revisions, newest first. Revision strings are ISO dates, so
    /// a descending lexical sort yields newest-first — a deterministic ordering for
    /// `server/discover`'s `supportedVersions` and the `-32004` error payload.
    public static var supportedDescending: [String] {
        supported.sorted(by: >)
    }
}
