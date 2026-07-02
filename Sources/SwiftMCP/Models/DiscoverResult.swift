//
//  DiscoverResult.swift
//  SwiftMCP
//
//  The result of the modern `server/discover` request (MCP `2026-07-28`, SEP-2575).
//  A stateless client calls `server/discover` to learn which protocol revisions a
//  server can negotiate and what it can do — the modern replacement for probing via
//  the `initialize` handshake.
//

import Foundation

/// The result of a `server/discover` request.
///
/// Mirrors ``InitializeResult`` (same `capabilities` / `serverInfo`) but adds the
/// negotiable-version list and optional caching hints, and carries no negotiated
/// `protocolVersion` — discovery precedes version selection.
public struct DiscoverResult: Codable, Sendable {
    /// Discriminator for the result shape. `"complete"` when the server returns
    /// its full capability set in one response (the only shape SwiftMCP emits).
    public var resultType: String

    /// The protocol revisions the server can negotiate, newest first.
    public var supportedVersions: [String]

    /// The server's capabilities (same shape as the initialize response).
    public var capabilities: ServerCapabilities

    /// Information about the server (name, title, version, icons, …).
    public var serverInfo: Implementation

    /// Optional human-oriented usage guidance, if the server provides any.
    public var instructions: String?

    /// Optional cache lifetime hint in milliseconds (SEP-2549). `nil` = unset.
    public var ttlMs: Int?

    /// Optional cache scope hint, e.g. `"public"` (SEP-2549). `nil` = unset.
    public var cacheScope: String?

    public init(
        resultType: String = "complete",
        supportedVersions: [String],
        capabilities: ServerCapabilities,
        serverInfo: Implementation,
        instructions: String? = nil,
        ttlMs: Int? = nil,
        cacheScope: String? = nil
    ) {
        self.resultType = resultType
        self.supportedVersions = supportedVersions
        self.capabilities = capabilities
        self.serverInfo = serverInfo
        self.instructions = instructions
        self.ttlMs = ttlMs
        self.cacheScope = cacheScope
    }
}
