import Foundation

public extension OAuthConfiguration {
    init?(issuer: URL,
         audience: String? = nil,
         clientID: String? = nil,
         clientSecret: String? = nil,
         transparentProxy: Bool = false) async {
        let configURL = issuer.appendingPathComponent(".well-known/openid-configuration")

        do {
            let (data, response) = try await URLSession.shared.data(from: configURL)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                return nil
            }
            
            let config = try JSONDecoder().decode(OIDCWellKnownConfiguration.self, from: data)

            self.init(
                issuer: config.issuer,
                authorizationEndpoint: config.authorization_endpoint,
                tokenEndpoint: config.token_endpoint,
                introspectionEndpoint: config.introspection_endpoint,
                jwksEndpoint: config.jwks_uri,
                audience: audience,
                clientID: clientID,
                clientSecret: clientSecret,
                registrationEndpoint: config.registration_endpoint,
                transparentProxy: transparentProxy
            )
        } catch {
            return nil
        }
    }
}
