//
//  ProcessIdentity.swift
//  SwiftMCP
//
//  POSIX process identity, behind one platform-conditional surface.
//
//  These values feed the Bonjour TXT record and the `.localUser` instance name,
//  both of which live in the always-on core and therefore compile on every
//  platform SwiftMCP supports — including Windows and Android, where the raw
//  POSIX calls are not in scope. Rather than sprinkling `#if os(...)` through the
//  call sites, everything unavailable resolves to `nil` here and the callers
//  degrade honestly: no pid in the TXT record, no uid in a fallback name.
//
//  Nothing is lost in practice — the Bonjour transport needs the Network
//  framework, so the platforms missing these calls cannot advertise anyway.
//

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Bionic)
import Bionic
#elseif canImport(Android)
import Android
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

/// The current process's POSIX identity, where the platform has one.
internal enum ProcessIdentity {
    /// The current process id, or `nil` on platforms without POSIX pids.
    internal static var processID: Int32? {
        #if os(Windows)
        return nil
        #else
        return getpid()
        #endif
    }

    /// The current user id, or `nil` on platforms without POSIX uids.
    internal static var userID: UInt32? {
        #if os(Windows)
        return nil
        #else
        return UInt32(getuid())
        #endif
    }

    /// Whether `processID` names a live process.
    ///
    /// `nil` when the platform cannot answer. `EPERM` counts as alive: the
    /// process exists, we simply do not own it — treating that as dead would
    /// discard a perfectly good advertisement from another user's daemon.
    internal static func isRunning(_ processID: Int32) -> Bool? {
        #if os(Windows)
        return nil
        #else
        if kill(processID, 0) == 0 { return true }
        return errno == EPERM
        #endif
    }
}
