//
//  ProcessIdentity.swift
//  SwiftMCP
//
//  Process identity for the Bonjour TXT record and the `.localUser` instance
//  name, behind one surface that compiles everywhere.
//
//  Both callers live in the always-on core, so they build on every platform
//  SwiftMCP supports — including Windows and Android, where the raw POSIX calls
//  are not in scope and the C-library overlay module is spelled differently on
//  each. Guessing at that spelling is how this broke the first time; the pid now
//  comes from Foundation, which is portable by construction, and the two values
//  with no Foundation equivalent are Darwin-gated.
//
//  Nothing is lost by that gating: `TCPBonjourTransport` needs the Network
//  framework, so no other platform can advertise or discover in the first place.
//

import Foundation

#if canImport(Darwin)
import Darwin
#endif

/// The current process's identity, where the platform can answer.
internal enum ProcessIdentity {
    /// The current process id.
    ///
    /// Foundation's, not `getpid()` — same value, no platform-specific import.
    internal static var processID: Int32 {
        ProcessInfo.processInfo.processIdentifier
    }

    /// The current user id, or `nil` where POSIX uids are unavailable.
    ///
    /// Only ever a fallback: `.localUser` names come from `NSUserName()`, which
    /// is portable and non-empty in every context that can run the transport.
    internal static var userID: UInt32? {
        #if canImport(Darwin)
        return UInt32(getuid())
        #else
        return nil
        #endif
    }

    /// Whether `processID` names a live process, or `nil` where the platform
    /// cannot answer.
    ///
    /// `EPERM` counts as alive: the process exists, we simply do not own it.
    /// Reporting that as dead would discard a working advertisement published by
    /// another user's daemon.
    internal static func isRunning(_ processID: Int32) -> Bool? {
        #if canImport(Darwin)
        if kill(processID, 0) == 0 { return true }
        return errno == EPERM
        #else
        return nil
        #endif
    }
}
