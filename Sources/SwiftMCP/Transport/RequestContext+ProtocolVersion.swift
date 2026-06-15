//
//  RequestContext+ProtocolVersion.swift
//  SwiftMCP
//
//  The single seam handlers consult to learn the protocol abilities in effect
//  for the current request, without caring which era produced them. Modern
//  (`2026-07-28`+) requests carry identity in `_meta`; legacy requests use the
//  session negotiated during the `initialize` handshake. Everything reads back
//  through ``RequestContext/protocolProfile`` so version-conditional behavior
//  branches on capabilities, not version strings.
//

import Foundation

public extension RequestContext {

    /// The protocol revision in effect for this request.
    ///
    /// Resolution order: the negotiated **legacy session** version, then the
    /// modern `_meta` value, then the server's current ``MCPProtocolVersion/latest``.
    ///
    /// The session is checked first on purpose: on the legacy (stateful) path a
    /// client commits to a version at `initialize`, and it must not be able to
    /// opt back into a different version by adding a per-request
    /// `_meta["io.modelcontextprotocol/protocolVersion"]`. The modern path is
    /// sessionless, so there `_meta` is the only source.
    var effectiveProtocolVersion: String {
        get async {
            if let version = await Session.current?.negotiatedProtocolVersion {
                return version
            }
            if let version = meta?.protocolVersion {
                return version
            }
            return MCPProtocolVersion.latest
        }
    }

    /// The capability profile for ``effectiveProtocolVersion``.
    ///
    /// Handlers gate version-conditional behavior on this, e.g.
    /// `if await context.protocolProfile.has(.jsonRPCBatching)`.
    var protocolProfile: ProtocolVersionProfile {
        get async {
            let version = await effectiveProtocolVersion
            return MCPProtocolVersion.profile(for: version) ?? .v20251125
        }
    }

    /// The client's declared capabilities: from the negotiated **legacy
    /// session** if present, otherwise the modern `_meta` value.
    ///
    /// Session-first for the same reason as ``effectiveProtocolVersion`` — a
    /// legacy client's negotiated capabilities are authoritative and cannot be
    /// overridden per-request via `_meta`.
    var effectiveClientCapabilities: ClientCapabilities? {
        get async {
            if let capabilities = await Session.current?.clientCapabilities {
                return capabilities
            }
            return meta?.clientCapabilities
        }
    }

    /// The log level requested for this single request (modern per-request
    /// logging via `_meta`). `nil` for legacy requests, which use the
    /// session-wide level set by `logging/setLevel`.
    var requestedLogLevel: LogLevel? { meta?.logLevel }

    /// Whether the request's negotiated protocol version supports `feature`.
    ///
    /// Convenience over ``protocolProfile`` for the common version-gating case:
    /// `if await RequestContext.current?.supports(.structuredToolOutput) ?? true`.
    func supports(_ feature: MCPFeature) async -> Bool {
        await protocolProfile.has(feature)
    }
}
