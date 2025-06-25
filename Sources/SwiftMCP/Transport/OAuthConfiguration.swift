import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Configuration for enabling OAuth validation on ``HTTPSSETransport``.
public struct OAuthConfiguration: Sendable {
    /// The issuer identifier for the authorization server.
    public let issuer: URL
    /// The OAuth authorization endpoint.
    public let authorizationEndpoint: URL
    /// The OAuth token endpoint.
    public let tokenEndpoint: URL
    /// Optional token introspection endpoint.
    public let introspectionEndpoint: URL?
    /// Optional JWKS endpoint for validating JWTs when no introspection endpoint is available.
    public let jwksEndpoint: URL?
    /// Expected audience ("aud" claim) for JWT validation.
    public let audience: String?
    /// Optional client identifier for introspection requests.
    public let clientID: String?
    /// Optional client secret for introspection requests.
    public let clientSecret: String?
    /// Optional custom validator closure.
    private let tokenValidator: (@Sendable (String?) async -> Bool)?
    /// The OAuth dynamic client registration endpoint (optional)
    public let registrationEndpoint: URL?
    /// The OAuth redirect URI (optional)
    public let redirectURI: String?

    public init(
        issuer: URL,
        authorizationEndpoint: URL,
        tokenEndpoint: URL,
        introspectionEndpoint: URL? = nil,
        jwksEndpoint: URL? = nil,
        audience: String? = nil,
        clientID: String? = nil,
        clientSecret: String? = nil,
        registrationEndpoint: URL? = nil,
        redirectURI: String? = nil,
        tokenValidator: (@Sendable (String?) async -> Bool)? = nil
    ) {
        self.issuer = issuer
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.introspectionEndpoint = introspectionEndpoint
        self.jwksEndpoint = jwksEndpoint
        self.audience = audience
        self.clientID = clientID
        self.clientSecret = clientSecret
        self.registrationEndpoint = registrationEndpoint
        self.redirectURI = redirectURI
        self.tokenValidator = tokenValidator
    }

    /// Validate the provided bearer token either using the custom validator,
    /// introspection, or by checking JWT claims against the issuer's JWKS.
    public func validate(token: String?) async -> Bool {
        guard let token = token else { return false }

        if let tokenValidator {
            return await tokenValidator(token)
        }

        if let introspectionEndpoint {
            var request = URLRequest(url: introspectionEndpoint)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            let body = "token=\(token)"
            if let clientID, let clientSecret {
                let credentials = "\(clientID):\(clientSecret)"
                if let data = credentials.data(using: .utf8) {
                    let b64 = data.base64EncodedString()
                    request.setValue("Basic \(b64)", forHTTPHeaderField: "Authorization")
                }
            }
            request.httpBody = body.data(using: .utf8)

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                    return false
                }
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    if let active = json["active"] as? Bool { return active }
                    if json["sub"] != nil { return true }
                }
                return false
            } catch {
                return false
            }
        }

        return await validateJWT(token: token)
    }

    /// Decode and validate a JWT using the configured JWKS endpoint.
    private func validateJWT(token: String) async -> Bool {
        let parts = token.split(separator: ".")
        guard parts.count == 3 else { return false }

        func decodePart(_ str: Substring) -> Data? {
            var base = str.replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
            let padding = 4 - base.count % 4
            if padding < 4 { base.append(String(repeating: "=", count: padding)) }
            return Data(base64Encoded: base)
        }

        guard let headerData = decodePart(parts[0]),
              let payloadData = decodePart(parts[1]),
              let header = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any],
              let payload = try? JSONSerialization.jsonObject(with: payloadData) as? [String: Any]
        else { return false }

        if let iss = payload["iss"] as? String, iss != issuer.absoluteString { return false }
        if let aud = audience, let tokenAud = payload["aud"] as? String, aud != tokenAud { return false }
        if let exp = payload["exp"] as? Double, exp < Date().timeIntervalSince1970 { return false }
        if let nbf = payload["nbf"] as? Double, nbf > Date().timeIntervalSince1970 { return false }

        guard let kid = header["kid"] as? String else { return false }

        let jwksURL = jwksEndpoint ?? issuer.appendingPathComponent(".well-known/jwks.json")
        do {
            let (data, response) = try await URLSession.shared.data(from: jwksURL)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            let jwks = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let keys = jwks?["keys"] as? [[String: Any]] ?? []
            return keys.contains { ($0["kid"] as? String) == kid }
        } catch {
            return false
        }
    }

    // MARK: - Metadata helpers

    /// Metadata for the `/.well-known/oauth-authorization-server` endpoint.
    public struct AuthorizationServerMetadata: Encodable {
        public let issuer: String
        public let authorization_endpoint: String
        public let token_endpoint: String
        public let introspection_endpoint: String?
        public let jwks_uri: String?
        public let response_types_supported: [String]
        public let grant_types_supported: [String]
        public let scopes_supported: [String]
        public let registration_endpoint: String?
        public let code_challenge_methods_supported: [String]?
    }

    /// Metadata for the `/.well-known/oauth-protected-resource` endpoint.
    public struct ProtectedResourceMetadata: Encodable {
        public let resource: String
        public let issuer: String
        public let token_endpoint: String
        public let jwks_uri: String?
        public let scopes_supported: [String]
    }

    public func authorizationServerMetadata() -> AuthorizationServerMetadata {
        let regEndpoint = registrationEndpoint?.absoluteString
        print("[OAuthConfiguration] registration_endpoint: \(String(describing: regEndpoint))")
        // Ensure authorization_endpoint ends with /authorize
        let authEndpoint: String
        if authorizationEndpoint.path.hasSuffix("/authorize") {
            authEndpoint = authorizationEndpoint.absoluteString
        } else {
            authEndpoint = issuer.appendingPathComponent("authorize").absoluteString
        }
        let meta = AuthorizationServerMetadata(
            issuer: issuer.absoluteString,
            authorization_endpoint: authEndpoint,
            token_endpoint: tokenEndpoint.absoluteString,
            introspection_endpoint: introspectionEndpoint?.absoluteString,
            jwks_uri: (jwksEndpoint ?? issuer.appendingPathComponent(".well-known/jwks.json")).absoluteString,
            response_types_supported: ["code", "token"],
            grant_types_supported: ["authorization_code", "client_credentials", "refresh_token"],
            scopes_supported: ["openid", "profile", "email"],
            registration_endpoint: regEndpoint,
            code_challenge_methods_supported: ["S256"]
        )
        print("[OAuthConfiguration] authorizationServerMetadata: \(meta)")
        return meta
    }

    public func protectedResourceMetadata(resourceBaseURL: String? = nil) -> ProtectedResourceMetadata {
        ProtectedResourceMetadata(
            resource: resourceBaseURL ?? issuer.absoluteString,
            issuer: issuer.absoluteString,
            token_endpoint: tokenEndpoint.absoluteString,
            jwks_uri: (jwksEndpoint ?? issuer.appendingPathComponent(".well-known/jwks.json")).absoluteString,
            scopes_supported: ["openid", "profile", "email"]
        )
    }
}
