#if Client
import Foundation

extension MCPServerProxy {
    /// Updates ``eraPreference``; takes effect on the next `connect()`.
    public func setEraPreference(_ preference: MCPClientEraPreference) {
        eraPreference = preference
    }

    /// Updates ``preferredProtocolVersion``; takes effect on the next `connect()`.
    public func setPreferredProtocolVersion(_ version: String?) {
        preferredProtocolVersion = version
    }

    /// Replaces ``meta`` (base `_meta` included on every request, e.g. `accessToken`).
    public func setMeta(_ meta: JSONDictionary) {
        self.meta = meta
    }
}
#endif
