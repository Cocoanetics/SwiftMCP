//
//  WebhookURLPolicy.swift
//  SwiftMCP
//
//  SSRF guard for webhook callback URLs: https only, no private, loopback or
//  link-local targets, optional port and host allowlists, and a check of the
//  addresses a host resolves to (DNS rebinding).
//

import Foundation

/// Why a webhook URL was rejected.
public enum WebhookURLPolicyError: Error, Equatable, Sendable {
    case invalidURL
    case schemeNotAllowed(String)
    case credentialsNotAllowed
    case hostNotAllowed(String)
    case portNotAllowed(Int)
    case blockedAddress(String)
    case resolutionFailed(String)
}

/// Validates webhook callback URLs. Pure logic: DNS resolution is injected.
public struct WebhookURLPolicy: Sendable {
    /// Resolves a host name to numeric IP address strings.
    public typealias Resolver = @Sendable (String) async throws -> [String]

    /// Allowed ports; defaults to 443 only.
    public var allowedPorts: Set<Int>

    /// When non-nil, only these hosts (case-insensitive) are accepted.
    public var allowedHosts: Set<String>?

    public init(allowedPorts: Set<Int> = [443], allowedHosts: Set<String>? = nil) {
        self.allowedPorts = allowedPorts
        self.allowedHosts = allowedHosts.map { Set($0.map { $0.lowercased() }) }
    }

    /// Validates the URL syntactically and, for IP-literal hosts, by address.
    /// Returns the host to connect to (lowercased, without brackets).
    @discardableResult
    public func validate(_ urlString: String) throws -> (host: String, port: Int) {
        guard let components = URLComponents(string: urlString),
              var host = components.host, !host.isEmpty else {
            throw WebhookURLPolicyError.invalidURL
        }
        guard let scheme = components.scheme?.lowercased() else { throw WebhookURLPolicyError.invalidURL }
        guard scheme == "https" else { throw WebhookURLPolicyError.schemeNotAllowed(scheme) }
        guard components.user == nil, components.password == nil else {
            throw WebhookURLPolicyError.credentialsNotAllowed
        }

        host = host.lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        if host.hasSuffix(".") { host.removeLast() }

        let port = components.port ?? 443
        guard allowedPorts.contains(port) else { throw WebhookURLPolicyError.portNotAllowed(port) }

        if let allowedHosts, !allowedHosts.contains(host) {
            throw WebhookURLPolicyError.hostNotAllowed(host)
        }

        if host == "localhost" || host.hasSuffix(".localhost") {
            throw WebhookURLPolicyError.blockedAddress(host)
        }
        if let parsed = IPAddress(host) {
            try check(parsed, original: host)
        }
        return (host, port)
    }

    /// Validates the URL, then resolves its host and rejects it if *any*
    /// resolved address is blocked. Callers must connect to one of the returned
    /// addresses (not re-resolve) to close the DNS-rebinding window.
    public func validate(_ urlString: String, resolver: Resolver) async throws -> [String] {
        let (host, _) = try validate(urlString)
        if IPAddress(host) != nil { return [host] }

        let addresses: [String]
        do {
            addresses = try await resolver(host)
        } catch {
            throw WebhookURLPolicyError.resolutionFailed(host)
        }
        guard !addresses.isEmpty else { throw WebhookURLPolicyError.resolutionFailed(host) }
        try validateResolved(addresses)
        return addresses
    }

    /// Rejects the set if any address is unparseable or blocked.
    public func validateResolved(_ addresses: [String]) throws {
        for address in addresses {
            guard let parsed = IPAddress(address) else { throw WebhookURLPolicyError.blockedAddress(address) }
            try check(parsed, original: address)
        }
    }

    /// Whether an IP literal is in a private, loopback, link-local or otherwise non-public range.
    public static func isBlocked(address: String) -> Bool {
        guard let parsed = IPAddress(address) else { return true }
        return parsed.isBlocked
    }

    private func check(_ parsed: IPAddress, original: String) throws {
        if parsed.isBlocked { throw WebhookURLPolicyError.blockedAddress(original) }
    }
}

/// Minimal IPv4/IPv6 literal parser and classifier.
struct IPAddress {
    enum Storage {
        case ipv4([UInt8])
        case ipv6([UInt8])
    }

    let storage: Storage

    init?(_ string: String) {
        if let ipv4Bytes = Self.parseIPv4(string) {
            storage = .ipv4(ipv4Bytes)
        } else if let ipv6Bytes = Self.parseIPv6(string) {
            storage = .ipv6(ipv6Bytes)
        } else {
            return nil
        }
    }

    var isBlocked: Bool {
        switch storage {
        case .ipv4(let bytes):
            return Self.isBlockedV4(bytes)
        case .ipv6(let bytes):
            if bytes.allSatisfy({ $0 == 0 }) { return true }                       // ::
            if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return true } // ::1
            if bytes[0] & 0xFE == 0xFC { return true }                             // fc00::/7
            if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0x80 { return true }             // fe80::/10 link-local
            if bytes[0] == 0xFE && bytes[1] & 0xC0 == 0xC0 { return true }             // fec0::/10 site-local
            if bytes[0] == 0xFF { return true }                                    // multicast
            if bytes[0..<4] == [0x20, 0x01, 0x0D, 0xB8] { return true }        // documentation
            if bytes[0..<6] == [0x00, 0x64, 0xFF, 0x9B, 0x00, 0x01] { return true } // local-use NAT64 (RFC 8215)
            // IPv4-mapped (::ffff:a.b.c.d), IPv4-compatible (::a.b.c.d) and NAT64 (64:ff9b::/96)
            let mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xFF && bytes[11] == 0xFF
            let compatible = bytes[0..<12].allSatisfy { $0 == 0 }
            let nat64 = bytes[0..<4] == [0x00, 0x64, 0xFF, 0x9B] && bytes[4..<12].allSatisfy { $0 == 0 }
            if mapped || compatible || nat64 { return Self.isBlockedV4(Array(bytes[12..<16])) }
            return false
        }
    }

    private static func isBlockedV4(_ bytes: [UInt8]) -> Bool {
        switch (bytes[0], bytes[1], bytes[2]) {
        case (0, _, _), (10, _, _), (127, _, _): return true
        case (100, 64...127, _): return true                // CGNAT
        case (169, 254, _): return true                     // link-local, cloud metadata
        case (172, 16...31, _): return true
        case (192, 0, 0), (192, 0, 2): return true          // IETF protocol, TEST-NET-1
        case (192, 168, _): return true
        case (198, 18...19, _), (198, 51, 100): return true // benchmarking, TEST-NET-2
        case (203, 0, 113): return true                     // TEST-NET-3
        case (224...255, _, _): return true                 // multicast, reserved, broadcast
        default: return false
        }
    }

    private static func parseIPv4(_ string: String) -> [UInt8]? {
        let parts = string.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        var result: [UInt8] = []
        for part in parts {
            guard !part.isEmpty, part.count <= 3, part.allSatisfy({ $0.isASCII && $0.isNumber }),
                  let value = UInt8(part) else { return nil }
            result.append(value)
        }
        return result
    }

    private static func parseIPv6(_ input: String) -> [UInt8]? {
        var string = input
        if let zone = string.firstIndex(of: "%") { string = String(string[..<zone]) }
        guard string.contains(":") else { return nil }

        var tailV4: [UInt8]?
        if let lastColon = string.lastIndex(of: ":"), string[string.index(after: lastColon)...].contains(".") {
            guard let ipv4Bytes = parseIPv4(String(string[string.index(after: lastColon)...])) else { return nil }
            tailV4 = ipv4Bytes
            string = String(string[...lastColon]) + "0:0"
        }

        let halves = string.components(separatedBy: "::")
        guard halves.count <= 2 else { return nil }

        func groups(_ text: String) -> [UInt16]? {
            if text.isEmpty { return [] }
            var out: [UInt16] = []
            for piece in text.split(separator: ":", omittingEmptySubsequences: false) {
                guard !piece.isEmpty, piece.count <= 4, let value = UInt16(piece, radix: 16) else { return nil }
                out.append(value)
            }
            return out
        }

        guard let head = groups(halves[0]) else { return nil }
        var all: [UInt16]
        if halves.count == 2 {
            guard let tail = groups(halves[1]), head.count + tail.count < 8 else { return nil }
            all = head + Array(repeating: 0, count: 8 - head.count - tail.count) + tail
        } else {
            guard head.count == 8 else { return nil }
            all = head
        }

        var bytes = all.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        if let tailV4 { bytes.replaceSubrange(12..<16, with: tailV4) }
        return bytes
    }
}
