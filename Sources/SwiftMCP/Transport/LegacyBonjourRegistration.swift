#if Server && canImport(Network)
import dnssd

/// A supplemental DNS-SD registration that points legacy service-type browsers
/// at the TCP port owned by the primary `NWListener`.
internal final class LegacyBonjourRegistration: @unchecked Sendable {
    private var reference: DNSServiceRef?

    internal init(name: String, type: String, domain: String, port: UInt16) throws {
        var reference: DNSServiceRef?
        let error = DNSServiceRegister(
            &reference,
            0,
            0,
            name,
            type,
            domain,
            nil,
            port.bigEndian,
            0,
            nil,
            nil,
            nil
        )
        guard error == kDNSServiceErr_NoError, let reference else {
            throw TransportError.bindingFailed("DNS-SD registration failed with error \(error)")
        }
        self.reference = reference
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
