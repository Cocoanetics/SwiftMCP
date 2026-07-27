//
//  BonjourTXTResolver.swift
//  SwiftMCP
//
//  Reads the TXT record of a discovered service.
//
//  This exists because `NWBrowser` cannot deliver TXT for the local scopes.
//  Measured on macOS: a plain `.bonjour` browse reports `metadata == .none`
//  regardless of how the service was registered, and the `.bonjourWithTXTRecord`
//  descriptor — which does deliver TXT — cannot see `kDNSServiceInterfaceIndexLocalOnly`
//  registrations at all. `DNSServiceResolve` sees both, so local-scope clients
//  resolve on demand.
//
//  Not trait-gated: both the client (reading) and the server (diagnostics) need it.
//

#if canImport(dnssd)
import Foundation
import dnssd

/// Resolves TXT records for discovered MCP Bonjour services.
internal enum BonjourTXTResolver {
    /// `kDNSServiceInterfaceIndexLocalOnly` (-1), not surfaced as a typed constant.
    internal static let localOnlyInterfaceIndex = UInt32(bitPattern: Int32(-1))
    /// `kDNSServiceInterfaceIndexAny` (0).
    internal static let anyInterfaceIndex: UInt32 = 0

    /// Queue libdispatch pumps resolve sockets on.
    ///
    /// The blocking `select()` loop this replaces ran on whatever thread called
    /// it — including Swift-concurrency cooperative threads, whose pool is sized
    /// to the core count. Stalling one on an mDNS round trip starves every other
    /// async task in the process, which is exactly how this surfaced: an
    /// unrelated timing-bounded test failing intermittently on a small CI runner.
    private static let queue = DispatchQueue(label: "com.cocoanetics.SwiftMCP.BonjourTXTResolver")

    /// Resolves one service's TXT record.
    ///
    /// Returns `nil` on timeout rather than throwing. Absent TXT means *unknown*,
    /// never *incompatible* — a caller that failed closed here would reject a
    /// working server because of a timing race, which is the same silent-failure
    /// shape this whole redesign exists to remove.
    internal static func resolve(
        instanceName: String,
        scope: DiscoveryScope,
        type: String = MCPBonjour.serviceType,
        timeout: TimeInterval = 2
    ) async -> BonjourTXTRecord? {
        final class Box: @unchecked Sendable {
            private let lock = NSLock()
            private var stored: BonjourTXTRecord?
            var record: BonjourTXTRecord? {
                get { lock.withLock { stored } }
                set { lock.withLock { stored = newValue } }
            }
        }
        let box = Box()
        let context = Unmanaged.passUnretained(box).toOpaque()

        let callback: DNSServiceResolveReply = { _, _, _, error, _, _, _, txtLength, txtRecord, context in
            guard error == kDNSServiceErr_NoError, let context else { return }
            let box = Unmanaged<Box>.fromOpaque(context).takeUnretainedValue()
            guard let txtRecord, txtLength > 0 else {
                box.record = BonjourTXTRecord(entries: [:])
                return
            }
            box.record = BonjourTXTRecord.decode(dnssdBytes: txtRecord, count: Int(txtLength))
        }

        var reference: DNSServiceRef?
        let interface = scope.isLocalOnly ? localOnlyInterfaceIndex : anyInterfaceIndex
        let status = DNSServiceResolve(
            &reference, 0, interface,
            instanceName, type, scope.domain, callback, context
        )
        guard status == kDNSServiceErr_NoError, let reference else { return nil }
        DNSServiceSetDispatchQueue(reference, queue)
        defer { queue.async { DNSServiceRefDeallocate(reference) } }

        // Yields instead of blocking: the callback lands on `queue`.
        let deadline = Date().addingTimeInterval(timeout)
        while box.record == nil, Date() < deadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return box.record
    }
}
#endif
