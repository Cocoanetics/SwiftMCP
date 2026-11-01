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
    /// Prefer a bearer / user identity when present. Legacy sessions (those that
    /// completed `initialize`) bind to the stable session id. Ephemeral modern
    /// sessions are not an identity — without a token they share the
    /// `"anonymous"` principal and the unguessable task id is the capability.
    public static func current() async -> MCPTaskPrincipal {
        if let token = RequestContext.current?.meta?.accessToken, !token.isEmpty {
            return MCPTaskPrincipal(rawValue: "token:\(token)")
        }
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
        return MCPTaskPrincipal(rawValue: "anonymous")
    }
}
