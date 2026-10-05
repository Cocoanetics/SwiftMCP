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

    /// Whether `versions` includes at least one modern (`2026-07-28`-era) revision.
    public static func includesModernEra(_ versions: Set<String>) -> Bool {
        versions.contains(where: isModern)
    }

    /// Whether this server's negotiable revisions (``supported``) include a modern
    /// era — i.e. whether `server/discover` can truthfully describe one. `false`
    /// until the dual-era rollout (#137) adds a modern revision to ``supported``.
    public static var supportsModernEra: Bool { includesModernEra(supported) }
}
