//
//  ProtocolVersionProfile.swift
//  SwiftMCP
//
//  Codifies each MCP protocol revision's abilities as a *set of feature keys*,
//  so the runtime can branch on capabilities (`profile.has(.jsonRPCBatching)`)
//  rather than hard-coding version strings. Lives in the always-on core (not
//  behind the `Server` trait): both the server runtime and the client
//  (`MCPServerProxy`) consult it during version negotiation without linking the
//  HTTP transport.
//
//  This is the pure data model (Phase 0 of the 2026-07-28 adoption plan). It
//  describes versions that are not yet negotiable — `profile(for:)` is
//  intentionally a superset of `MCPProtocolVersion.supported`.
//

import Foundation

/// The two interoperability eras defined by the MCP specification.
///
/// - `legacy`: revisions that establish a session via the `initialize`
///   handshake (`2025-11-25` and earlier).
/// - `modern`: revisions that convey version, identity and capabilities as
///   per-request metadata (`2026-07-28` and later).
public enum MCPProtocolEra: String, Sendable, CaseIterable {
    case legacy
    case modern
}

/// A single capability of the Model Context Protocol.
///
/// Each case is a stable *key*. Adding a protocol feature means adding one case
/// here; ``ProtocolVersionProfile`` and every call site that reads it stay
/// unchanged. The `String` raw values are stable identifiers usable in tests,
/// logs and diagnostics.
public enum MCPFeature: String, Sendable, CaseIterable {

    // MARK: Lifecycle / transport

    /// JSON-RPC batching (array payloads). Added `2025-03-26`, removed `2025-06-18`.
    case jsonRPCBatching
    /// The `initialize` / `notifications/initialized` handshake (legacy only).
    case initializeHandshake
    /// Transport-maintained session identity (legacy only).
    case protocolLevelSessions
    /// A standalone server→client SSE stream opened with HTTP `GET` (legacy only).
    case standaloneGetStream
    /// Resumable streams via `Last-Event-ID` (legacy Streamable HTTP only).
    case resumableStreams
    /// The `MCP-Protocol-Version` HTTP header. Introduced `2025-06-18`.
    case protocolVersionHeader

    /// Per-request `_meta` carries protocol version, client identity and capabilities (modern).
    case perRequestMetadata
    /// The `server/discover` RPC (modern; servers MUST implement it).
    case serverDiscover
    /// Required `Mcp-Method` / `Mcp-Name` HTTP headers (modern).
    case standardRequestHeaders
    /// `x-mcp-header` tool-parameter mirroring into `Mcp-Param-*` headers (modern).
    case xMcpHeader

    // MARK: Server → client interaction

    /// Live server-initiated JSON-RPC requests (sampling/elicitation/roots) (legacy).
    case serverInitiatedRequests
    /// Multi Round-Trip Requests: `InputRequiredResult` / `inputResponses` (modern).
    case mrtr
    /// `resources/subscribe` + `resources/unsubscribe` (legacy).
    case subscribeUnsubscribe
    /// The `subscriptions/listen` long-lived notification stream (modern).
    case subscriptionsListen

    // MARK: Payload features

    /// Elicitation of structured user input. Added `2025-06-18`.
    case elicitation
    /// Structured tool output (`outputSchema` / `structuredContent`). Added `2025-06-18`.
    case structuredToolOutput
    /// Resource links in tool-call results. Added `2025-06-18`.
    case resourceLinks
    /// Tool annotations (read-only / destructive hints). Added `2025-03-26`.
    case toolAnnotations
    /// Audio content blocks. Added `2025-03-26`.
    case audioContent
    /// The declared `completions` capability. Added `2025-03-26`.
    case completionsCapability
    /// Human-friendly `title` fields distinct from programmatic `name`. Added `2025-06-18`.
    case titleField

    // MARK: Utilities

    /// The `ping` request. Removed in modern.
    case ping
    /// The `logging/setLevel` request (session-scoped log level). Removed in modern.
    case loggingSetLevel
    /// Per-request log level via `_meta` (`io.modelcontextprotocol/logLevel`) (modern).
    case perRequestLogLevel
    /// The `notifications/roots/list_changed` notification. Removed in modern.
    case rootsListChangedNotification
    /// Cacheable list/read results (`ttlMs` / `cacheScope`). Added `2026-07-28`.
    case cacheableListResults
}

/// The set of abilities a given protocol revision supports.
///
/// Handlers branch on `profile.has(.someFeature)` instead of comparing version
/// strings, and the few genuinely value-typed facets (error codes) derive from
/// the feature set rather than being stored. Build the per-version table with
/// ``deriving(_:era:adding:removing:)`` so each revision reads like its
/// changelog.
public struct ProtocolVersionProfile: Sendable, Hashable {

    /// The protocol revision string, e.g. `"2025-11-25"`.
    public let version: String

    /// Which interoperability era this revision belongs to.
    public let era: MCPProtocolEra

    /// The capabilities this revision supports.
    public let features: Set<MCPFeature>

    public init(version: String, era: MCPProtocolEra, features: Set<MCPFeature>) {
        self.version = version
        self.era = era
        self.features = features
    }

    /// Whether this revision supports `feature`.
    public func has(_ feature: MCPFeature) -> Bool {
        features.contains(feature)
    }

    /// `true` for revisions that use per-request metadata instead of a handshake.
    public var isModern: Bool { era == .modern }

    /// The JSON-RPC error code for a missing resource on `resources/read`.
    ///
    /// Modern revisions align with JSON-RPC and use `-32602` (Invalid Params);
    /// legacy revisions keep SwiftMCP's historical `-32001`.
    public var resourceNotFoundCode: Int {
        has(.perRequestMetadata) ? -32602 : -32001
    }

    /// The JSON-RPC error code for an unsupported protocol version
    /// (`UnsupportedProtocolVersionError`, modern negotiation).
    public var unsupportedVersionErrorCode: Int { -32004 }

    /// Derive a successor revision from this one — add what the new revision
    /// introduced, remove what it dropped. Mirrors how the spec changelogs read.
    public func deriving(
        _ version: String,
        era: MCPProtocolEra? = nil,
        adding: Set<MCPFeature> = [],
        removing: Set<MCPFeature> = []
    ) -> ProtocolVersionProfile {
        ProtocolVersionProfile(
            version: version,
            era: era ?? self.era,
            features: features.union(adding).subtracting(removing)
        )
    }
}

// MARK: - The version → abilities table

public extension ProtocolVersionProfile {

    /// `2024-11-05` baseline. Not negotiable today (absent from
    /// ``MCPProtocolVersion/supported``); only its HTTP+SSE transport survives
    /// as the deprecated legacy SSE routes. Present as the root of the
    /// ``deriving(_:era:adding:removing:)`` chain.
    static let v20241105 = ProtocolVersionProfile(
        version: "2024-11-05",
        era: .legacy,
        features: [
            .initializeHandshake, .protocolLevelSessions, .standaloneGetStream,
            .serverInitiatedRequests, .subscribeUnsubscribe,
            .ping, .loggingSetLevel, .rootsListChangedNotification
        ]
    )

    /// `2025-03-26`: Streamable HTTP, JSON-RPC batching, tool annotations,
    /// audio content and the declared `completions` capability.
    static let v20250326 = v20241105.deriving(
        "2025-03-26",
        adding: [
            .jsonRPCBatching, .resumableStreams,
            .toolAnnotations, .audioContent, .completionsCapability
        ]
    )

    /// `2025-06-18`: removes batching; adds the `MCP-Protocol-Version` header,
    /// elicitation, structured tool output, resource links and `title`.
    static let v20250618 = v20250326.deriving(
        "2025-06-18",
        adding: [
            .protocolVersionHeader, .elicitation, .structuredToolOutput,
            .resourceLinks, .titleField
        ],
        removing: [.jsonRPCBatching]
    )

    /// `2025-11-25`: no change to the *core* feature surface modelled here
    /// (experimental Tasks are handled via the extensions map, not as a core
    /// feature key).
    static let v20251125 = v20250618.deriving("2025-11-25")

    /// `2026-07-28` (modern): defined fresh rather than as a delta, since the
    /// stateless redesign removes most of the legacy surface.
    static let v20260728 = ProtocolVersionProfile(
        version: "2026-07-28",
        era: .modern,
        features: [
            .perRequestMetadata, .serverDiscover, .standardRequestHeaders,
            .xMcpHeader, .protocolVersionHeader,
            .mrtr, .subscriptionsListen,
            .elicitation, .structuredToolOutput, .resourceLinks,
            .toolAnnotations, .audioContent, .completionsCapability, .titleField,
            .perRequestLogLevel, .cacheableListResults
        ]
    )
}

// MARK: - Lookup

public extension MCPProtocolVersion {

    /// The modern (stateless, per-request-metadata) revision.
    ///
    /// Not yet part of ``supported``: the runtime can *describe* it via
    /// ``profile(for:)`` before it advertises or negotiates it.
    static let modern = "2026-07-28"

    /// Every revision SwiftMCP has a capability profile for.
    ///
    /// Intentionally a superset of ``supported`` (the set the server will
    /// negotiate): it also covers `2024-11-05` (context only) and ``modern``
    /// (described ahead of implementation).
    static var allKnownProfiles: [ProtocolVersionProfile] {
        [.v20241105, .v20250326, .v20250618, .v20251125, .v20260728]
    }

    /// The capability profile for `version`, or `nil` if it is unknown.
    static func profile(for version: String) -> ProtocolVersionProfile? {
        allKnownProfiles.first { $0.version == version }
    }
}
