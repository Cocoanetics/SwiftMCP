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
    /// Resolution order: the modern `_meta` value, then the legacy
    /// session-negotiated version, then the server's current ``MCPProtocolVersion/latest``.
    var effectiveProtocolVersion: String {
        get async {
            if let version = meta?.protocolVersion {
                return version
            }
            if let version = await Session.current?.negotiatedProtocolVersion {
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
            return MCPProtocolVersion.profile(for: version) ?? .v2025_11_25
        }
    }

    /// The client's declared capabilities, from `_meta` (modern) or the session
    /// (legacy).
    var effectiveClientCapabilities: ClientCapabilities? {
        get async {
            if let capabilities = meta?.clientCapabilities {
                return capabilities
            }
            return await Session.current?.clientCapabilities
        }
    }

    /// The log level requested for this single request (modern per-request
    /// logging via `_meta`). `nil` for legacy requests, which use the
    /// session-wide level set by `logging/setLevel`.
    var requestedLogLevel: LogLevel? { meta?.logLevel }
}
