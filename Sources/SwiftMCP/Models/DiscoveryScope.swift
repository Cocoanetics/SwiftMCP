//
//  DiscoveryScope.swift
//  SwiftMCP
//
//  How far an MCP-over-TCP service is advertised, and how far a client looks
//  for one. This lives in the always-on core (no trait gate) because both the
//  server transport and the client config express the same axis, and they must
//  agree — a server that advertises narrower than a client browses simply never
//  appears, with no diagnostic.
//

import Foundation

/// How far a Bonjour service reaches.
///
/// One value drives binding, advertising, *and* browsing, so advertising wider
/// than you serve is unrepresentable. This replaces the previous split between
/// `acceptLocalOnly` (server-side, and misleadingly named — it restricts to the
/// directly attached link, not to loopback) and `domain` (client-side).
public enum DiscoveryScope: Sendable, Hashable, CaseIterable {
    /// Same machine, same user. Registered local-only and bound to loopback.
    ///
    /// The default, because Bonjour instance names are machine-wide: two user
    /// accounts each running the same server would otherwise collide, and the
    /// second user's client would silently bind to the first user's process.
    case localUser

    /// Same machine, any user. Registered local-only and bound to loopback.
    ///
    /// For a deliberate service-account or multi-tenant daemon. The app takes
    /// on disambiguation itself.
    case localMachine

    /// The directly attached link. Registered and browsed over multicast.
    ///
    /// Opt-in: the transport has no authorization hook, so anything reachable
    /// here is reachable unauthenticated unless the app adds its own layer.
    case localNetwork

    /// Whether this scope keeps the service off the network entirely.
    public var isLocalOnly: Bool {
        switch self {
        case .localUser, .localMachine: return true
        case .localNetwork: return false
        }
    }

    /// The DNS-SD domain. Always `local.`; wide-area DNS-SD is out of scope.
    public var domain: String { "local." }
}

// MARK: - Instance-name derivation

extension DiscoveryScope {
    /// The instance name a server advertises for `base` under this scope.
    ///
    /// For the local scopes this is **symmetric**: a client on the same machine
    /// computes the identical string from the same base name, with no lookup and
    /// no configuration. That symmetry is load-bearing — if the two sides derived
    /// differently they would never meet.
    ///
    /// `.localNetwork` is deliberately *not* symmetric: the server qualifies with
    /// its own host name, which a remote client cannot know. Clients at that scope
    /// match on the TXT `name` entry instead — see ``canDeriveInstanceName``.
    public func instanceName(for base: String) -> String {
        switch self {
        case .localUser:
            return "\(base) (\(DiscoveryScope.userLabel))"
        case .localMachine:
            return base
        case .localNetwork:
            return "\(base) on \(DiscoveryScope.hostLabel)"
        }
    }

    /// Whether a client can derive the server's advertised instance name from the
    /// base name alone. False for `.localNetwork`, where the host component is
    /// unknowable remotely and matching goes through the TXT `name` entry.
    public var canDeriveInstanceName: Bool { isLocalOnly }

    /// The current user, for `.localUser` names. Falls back to the numeric uid
    /// when the login name is unavailable (daemon contexts without a home).
    static var userLabel: String {
        let name = NSUserName()
        guard name.isEmpty else { return name }
        guard let userID = ProcessIdentity.userID else { return "user" }
        return "uid \(userID)"
    }

    /// The host, for `.localNetwork` names. `ProcessInfo.hostName` rather than
    /// `Host.current().localizedName` — the latter is typically "Oliver's Mac",
    /// i.e. the owner's name broadcast to every device on the link.
    static var hostLabel: String {
        var host = ProcessInfo.processInfo.hostName
        if host.hasSuffix(".local") { host.removeLast(6) }
        if host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? "unknown host" : host
    }
}

// MARK: - Instance-name matching

extension String {
    /// Compares two DNS-SD instance names.
    ///
    /// Instance names are Net-Unicode (RFC 5198), so they are compared after NFC
    /// normalization — otherwise a precomposed `é` fails to match `e` + combining
    /// accent. Case folding is **ASCII-only and locale-independent**: the previous
    /// `localizedCaseInsensitiveCompare` made resolution depend on the device's
    /// locale, so a Turkish-locale client folded `I`/`ı` differently and found a
    /// different server than the same code did elsewhere.
    internal func matchesInstanceName(_ other: String) -> Bool {
        normalizedInstanceName == other.normalizedInstanceName
    }

    /// NFC-normalized, ASCII-lowercased form used for instance-name comparison.
    internal var normalizedInstanceName: String {
        var scalars = String.UnicodeScalarView()
        for scalar in precomposedStringWithCanonicalMapping.unicodeScalars {
            if scalar.value >= 0x41, scalar.value <= 0x5A,
               let lowered = Unicode.Scalar(scalar.value + 0x20) {
                scalars.append(lowered)
            } else {
                scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
