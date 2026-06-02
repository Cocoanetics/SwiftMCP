#if Server
import Foundation

// swiftlint:disable identifier_name
// Field names match the OIDC Discovery JSON wire format (RFC 8414 / OpenID Connect Discovery 1.0).
internal struct OIDCWellKnownConfiguration: Decodable, Sendable {
    let issuer: URL
    let authorization_endpoint: URL
    let token_endpoint: URL
    let introspection_endpoint: URL?
    let jwks_uri: URL
    let registration_endpoint: URL?
}
// swiftlint:enable identifier_name
#endif
