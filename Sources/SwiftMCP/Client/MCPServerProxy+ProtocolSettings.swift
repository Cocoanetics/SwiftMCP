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
}
#endif
