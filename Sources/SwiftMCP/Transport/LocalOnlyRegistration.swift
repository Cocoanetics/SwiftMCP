#if Server && canImport(Network)
import Foundation
import dnssd

/// A DNS-SD registration scoped to `kDNSServiceInterfaceIndexLocalOnly`, pointing
/// at the TCP port owned by the primary `NWListener`.
///
/// Network framework has no interface-scope parameter on `NWListener.Service`, so
/// the local scopes cannot be expressed through it — this is the only way to
/// register a service that is genuinely invisible off-box. `NWListener` still owns
/// binding and accepting; this only publishes.
///
/// Measured behaviour this design depends on:
///
/// - A `LocalOnly` registration **is** found by a plain `NWBrowser` (`.bonjour`),
///   and its results report `interfaces == [loopback]`.
/// - It is **not** found by `.bonjourWithTXTRecord`, so clients at local scope
///   browse plainly and read TXT on demand via ``resolveTXTRecord(instanceName:type:domain:timeout:)``.
/// - `DNSServiceResolve` at `LocalOnly` does return the TXT record.
internal final class LocalOnlyRegistration: @unchecked Sendable {
    /// Holds the name mDNSResponder confirmed, which differs from the requested
    /// name when it resolved a conflict by renaming.
    private final class NameBox: @unchecked Sendable { var name: String? }

    private var reference: DNSServiceRef?
    private let nameBox = NameBox()

    /// The instance name mDNSResponder actually registered, once confirmed.
    internal var resolvedName: String? { nameBox.name }

    /// `kDNSServiceInterfaceIndexLocalOnly` (-1), which is not surfaced to Swift
    /// as a typed constant.
    internal static let localOnlyInterfaceIndex = UInt32(bitPattern: Int32(-1))

    /// Registers `name` locally, advertising `port` and `txtRecord`.
    internal init(name: String, type: String, domain: String, port: UInt16, txtRecord: BonjourTXTRecord?) throws {
        var reference: DNSServiceRef?
        let txtBytes = txtRecord?.dnssdBytes ?? []
        let context = Unmanaged.passUnretained(nameBox).toOpaque()

        // The reply carries the name that was actually registered — mDNS renames
        // on conflict, and a server that cannot report its published identity
        // cannot be diagnosed once identity lives in the instance name.
        let callback: DNSServiceRegisterReply = { _, _, error, name, _, _, context in
            guard error == kDNSServiceErr_NoError, let name, let context else { return }
            Unmanaged<NameBox>.fromOpaque(context).takeUnretainedValue().name = String(cString: name)
        }

        let error: DNSServiceErrorType = txtBytes.withUnsafeBufferPointer { buffer in
            DNSServiceRegister(
                &reference,
                0,
                Self.localOnlyInterfaceIndex,
                name,
                type,
                domain,
                nil,
                port.bigEndian,
                UInt16(buffer.count),
                buffer.isEmpty ? nil : buffer.baseAddress,
                callback,
                context
            )
        }
        guard error == kDNSServiceErr_NoError, let reference else {
            throw TransportError.bindingFailed("Local-only DNS-SD registration failed with error \(error)")
        }
        self.reference = reference

        // Pump once so the confirmation callback lands; the name is wanted for
        // logging right away, not eventually.
        DNSServiceProcessResult(reference)
    }

    internal func stop() {
        guard let reference else { return }
        self.reference = nil
        DNSServiceRefDeallocate(reference)
    }

    deinit {
        stop()
    }
}

#endif
