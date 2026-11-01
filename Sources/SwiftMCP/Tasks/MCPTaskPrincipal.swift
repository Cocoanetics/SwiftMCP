//
//  MCPTaskPrincipal.swift
//  SwiftMCP
//
//  Ownership key for task isolation. Task IDs are unguessable handles; when a
//  stronger principal is available (bearer token / user / session) it is bound
//  at creation and checked on every subsequent tasks/* request.
//

import Foundation

/// The authorization principal that owns a task.
public struct MCPTaskPrincipal: Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// Resolves the principal for the current request / session context.
    ///
    /// Prefer the transport-authenticated session identity (user / bearer /
    /// initialize-bound session id) over client-controlled `_meta.accessToken`,
    /// so a stale or conflicting metadata token cannot rebind ownership. Fall
    /// back to `_meta.accessToken` only when no authenticated session identity
    /// exists. Ephemeral modern sessions without a token share `"anonymous"`
    /// and the unguessable task id is the capability.
    public static func current() async -> MCPTaskPrincipal {
        if let session = Session.current {
            if let userID = await session.userID, !userID.isEmpty {
                return MCPTaskPrincipal(rawValue: "user:\(userID)")
            }
            if let token = await session.accessToken, !token.isEmpty {
                return MCPTaskPrincipal(rawValue: "token:\(token)")
            }
            // Only legacy (initialize-bound) sessions are a stable principal.
            if await session.negotiatedProtocolVersion != nil {
                return MCPTaskPrincipal(rawValue: "session:\(session.id.uuidString)")
            }
        }
        if let token = RequestContext.current?.meta?.accessToken, !token.isEmpty {
            return MCPTaskPrincipal(rawValue: "token:\(token)")
        }
        return MCPTaskPrincipal(rawValue: "anonymous")
    }
}
