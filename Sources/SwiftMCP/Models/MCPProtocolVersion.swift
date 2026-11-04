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

    /// The revisions the legacy `initialize` handshake can negotiate.
    public static let legacySupported: Set<String> = [
        latest,
        intermediateHTTP,
        fallbackHTTP
    ]

    /// The full set of protocol revisions this package can negotiate: the legacy
    /// revisions plus ``modern``, which is reached through `server/discover`.
    public static let supported: Set<String> = legacySupported.union([modern])

    /// The negotiable revisions, newest first. Revision strings are ISO dates, so
    /// a descending lexical sort yields newest-first — a deterministic ordering for
    /// `server/discover`'s `supportedVersions` and the `-32004` error payload.
    public static var supportedDescending: [String] {
        supported.sorted(by: >)
    }

    /// The revisions a server advertises: ``supported`` by default, or only
    /// ``legacySupported`` when the server opts out of the modern era
    /// (`MCPServer.advertisesModernEra` returns `false`).
    public static func advertised(modernEra: Bool) -> Set<String> {
        modernEra ? supported : legacySupported
    }

    /// ``advertised(modernEra:)``, newest first.
    public static func advertisedDescending(modernEra: Bool) -> [String] {
        advertised(modernEra: modernEra).sorted(by: >)
    }

    /// Whether `versions` includes at least one modern (`2026-07-28`-era) revision.
    public static func includesModernEra(_ versions: Set<String>) -> Bool {
        versions.contains(where: isModern)
    }

    /// Whether this package's negotiable revisions (``supported``) include a modern
    /// era — i.e. whether `server/discover` can truthfully describe one. The #199
    /// safety net: `server/discover` answers `-32601` whenever this is `false`.
    public static var supportsModernEra: Bool { includesModernEra(supported) }
}
