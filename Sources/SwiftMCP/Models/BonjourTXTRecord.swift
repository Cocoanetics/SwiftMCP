//
//  BonjourTXTRecord.swift
//  SwiftMCP
//
//  The TXT record an MCP-over-TCP service advertises (RFC 6763 §6).
//
//  Every key here is framework-owned and populated by the transport. Apps do not
//  contribute entries: TXT rides in a single UDP response, and the one thing apps
//  were reaching for — "the same server is also at this HTTP endpoint" — is an MCP
//  concern that `serve(over:)` can fill in from the transport list it already has.
//

import Foundation

/// Framework-owned TXT entries for an MCP Bonjour advertisement.
public struct BonjourTXTRecord: Sendable, Hashable {
    /// Reserved keys. Apps cannot add entries, so this is the complete set.
    public enum Key {
        /// Version of the TXT layout itself (RFC 6763 §6.7).
        public static let txtVersion = "txtvers"
        /// The server's own name, which survives mDNS conflict renaming.
        public static let name = "name"
        /// The server's implementation version.
        public static let version = "ver"
        /// The newest MCP protocol revision the server can negotiate.
        public static let protocolVersion = "proto"
        /// Publishing process id. Local scopes only — meaningless across hosts.
        public static let processID = "pid"
        /// `port/path` at which the *same* server is reachable over HTTP/SSE.
        public static let httpEndpoint = "http"
    }

    /// Current TXT layout version.
    public static let layoutVersion = "1"

    public private(set) var entries: [String: String]

    public subscript(key: String) -> String? { entries[key] }

    /// Builds a record from already-decoded entries (browse or resolve results).
    public init(entries: [String: String]) {
        self.entries = entries
    }

    /// Builds the record a server advertises.
    ///
    /// - Parameters:
    ///   - serverName: `MCPServer.serverName`, or the base instance name.
    ///   - serverVersion: `MCPServer.serverVersion`, when known.
    ///   - protocolVersion: newest negotiable MCP revision.
    ///   - processID: publishing pid. Pass `nil` for `.localNetwork` — a pid from
    ///     another host names nothing locally, and checking it would confidently
    ///     answer about an unrelated local process.
    ///   - httpEndpoint: `"port/path"` when the same server is also served over
    ///     HTTP/SSE. Filled in by `serve(over:)`, not by the app.
    public init(
        serverName: String,
        serverVersion: String? = nil,
        protocolVersion: String? = nil,
        processID: Int32? = nil,
        httpEndpoint: String? = nil
    ) {
        var entries = [Key.txtVersion: Self.layoutVersion, Key.name: serverName]
        if let serverVersion { entries[Key.version] = serverVersion }
        if let protocolVersion { entries[Key.protocolVersion] = protocolVersion }
        if let processID { entries[Key.processID] = String(processID) }
        if let httpEndpoint { entries[Key.httpEndpoint] = httpEndpoint }
        self.entries = entries
    }

    // MARK: Convenience accessors

    public var serverName: String? { entries[Key.name] }
    public var serverVersion: String? { entries[Key.version] }
    public var protocolVersion: String? { entries[Key.protocolVersion] }
    public var processID: Int32? { entries[Key.processID].flatMap(Int32.init) }
    public var httpEndpoint: String? { entries[Key.httpEndpoint] }

    /// Whether the advertising process is still alive.
    ///
    /// Only meaningful when the record came from a local scope; `nil` when no pid
    /// was published. A stale advertisement from a wedged or killed process is the
    /// failure this catches.
    public var isPublisherAlive: Bool? {
        guard let processID else { return nil }
        return kill(processID, 0) == 0 || errno == EPERM
    }

    // MARK: Wire format

    /// The DNS-SD wire encoding: each entry a length-prefixed `key=value`.
    ///
    /// Entries longer than 255 bytes are dropped rather than truncated — a
    /// truncated entry would decode as a different value, which is worse than
    /// an absent one.
    public var dnssdBytes: [UInt8] {
        var bytes = [UInt8]()
        for key in entries.keys.sorted() {
            let pair = Array("\(key)=\(entries[key]!)".utf8)
            guard pair.count <= 255 else { continue }
            bytes.append(UInt8(pair.count))
            bytes.append(contentsOf: pair)
        }
        return bytes
    }

    /// Decodes the DNS-SD wire encoding produced by `DNSServiceResolve`.
    public static func decode(dnssdBytes bytes: UnsafePointer<UInt8>, count: Int) -> BonjourTXTRecord {
        var entries = [String: String]()
        var index = 0
        while index < count {
            let length = Int(bytes[index])
            index += 1
            guard length > 0, index + length <= count else { index += length; continue }
            let pair = String(decoding: UnsafeBufferPointer(start: bytes + index, count: length), as: UTF8.self)
            index += length
            guard let separator = pair.firstIndex(of: "=") else { continue }
            entries[String(pair[pair.startIndex..<separator])] = String(pair[pair.index(after: separator)...])
        }
        return BonjourTXTRecord(entries: entries)
    }
}
