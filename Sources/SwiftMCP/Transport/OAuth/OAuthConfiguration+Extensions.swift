import Foundation

internal struct OIDCWellKnownConfiguration: Decodable, Sendable {
    let issuer: URL
    let authorization_endpoint: URL
    let token_endpoint: URL
    let introspection_endpoint: URL?
    let jwks_uri: URL
    let registration_endpoint: URL?
}
