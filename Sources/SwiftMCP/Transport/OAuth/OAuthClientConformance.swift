#if Server || Client
import Foundation

/// Errors raised by the MCP OAuth conformance helpers.
public enum OAuthConformanceError: Error, Equatable, LocalizedError {
    /// The authorization response carried an `iss` that differs from the expected issuer (RFC 9207).
    case issuerMismatch(expected: String, received: String)
    /// The server advertised `authorization_response_iss_parameter_supported` but the response had no `iss`.
    case missingIssuer(expected: String)
    /// The registration request lacks a valid `application_type` (SEP-837).
    case invalidApplicationType(String?)
    /// A Client ID Metadata Document URL or document is invalid.
    case invalidClientIDMetadataDocument(String)

    public var errorDescription: String? {
        switch self {
        case .issuerMismatch(let expected, let received):
            return "Authorization response issuer '\(received)' does not match expected issuer '\(expected)'"
        case .missingIssuer(let expected):
            return "Authorization response is missing the required 'iss' parameter (expected '\(expected)')"
        case .invalidApplicationType(let value):
            return "Dynamic client registration requires application_type 'web' or 'native' (got \(value ?? "none"))"
        case .invalidClientIDMetadataDocument(let details):
            return "Invalid Client ID Metadata Document: \(details)"
        }
    }
}

/// RFC 9207 / SEP-2468: validation of the `iss` parameter of authorization responses.
public enum OAuthAuthorizationResponse {
    /// Validate the `iss` parameter of an authorization response.
    ///
    /// The comparison is an exact string comparison (RFC 9207 §2.4). When the server did not advertise
    /// `authorization_response_iss_parameter_supported`, an absent `iss` is tolerated, but a present
    /// one must still match.
    public static func validateIssuer(
        responseIssuer: String?,
        expectedIssuer: String,
        issuerParameterSupported: Bool
    ) throws {
        guard let responseIssuer else {
            if issuerParameterSupported { throw OAuthConformanceError.missingIssuer(expected: expectedIssuer) }
            return
        }
        guard responseIssuer == expectedIssuer else {
            throw OAuthConformanceError.issuerMismatch(expected: expectedIssuer, received: responseIssuer)
        }
    }

    /// Validate the `iss` query item of a redirect URI the client was called back on.
    public static func validateIssuer(
        redirectURL: URL,
        expectedIssuer: String,
        issuerParameterSupported: Bool
    ) throws {
        let items = URLComponents(url: redirectURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
        try validateIssuer(
            responseIssuer: items.first { $0.name == "iss" }?.value,
            expectedIssuer: expectedIssuer,
            issuerParameterSupported: issuerParameterSupported
        )
    }
}

/// SEP-837: dynamic client registration requests must declare an `application_type`.
public enum OAuthClientRegistrationValidator {
    public static let allowedApplicationTypes: Set<String> = ["web", "native"]

    /// Validate a registration request body (JSON object).
    public static func validate(requestBody: Data?) throws {
        guard let requestBody,
              let json = try? JSONSerialization.jsonObject(with: requestBody) as? [String: Any],
              let type = json["application_type"] as? String,
              allowedApplicationTypes.contains(type) else {
            let object = requestBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
            let value = object?["application_type"] as? String
            throw OAuthConformanceError.invalidApplicationType(value)
        }
    }
}

/// Client credentials obtained from an authorization server, bound to its issuer (SEP-2352).
public struct OAuthClientCredentials: Sendable, Equatable, Codable {
    public let issuer: String
    public let clientID: String
    public let clientSecret: String?

    public init(issuer: String, clientID: String, clientSecret: String? = nil) {
        self.issuer = issuer
        self.clientID = clientID
        self.clientSecret = clientSecret
    }
}

/// Stores client credentials per authorization-server issuer so they are never reused across issuers.
public actor OAuthClientCredentialStore {
    private var stored: [String: OAuthClientCredentials] = [:]
    private var inFlight: [String: Task<OAuthClientCredentials, Error>] = [:]

    public init() {}

    /// Credentials previously registered with exactly this issuer, if any.
    public func credentials(for issuer: String) -> OAuthClientCredentials? {
        stored[issuer]
    }

    public func save(_ credentials: OAuthClientCredentials) {
        stored[credentials.issuer] = credentials
    }

    public func remove(issuer: String) {
        stored[issuer] = nil
    }

    /// Return credentials for `issuer`, calling `register` (dynamic registration) when none are bound to it.
    public func credentials(
        for issuer: String,
        register: @escaping @Sendable (String) async throws -> OAuthClientCredentials
    ) async throws -> OAuthClientCredentials {
        if let existing = stored[issuer] { return existing }
        // Actors are reentrant at `await`: share one in-flight registration per issuer.
        if let pending = inFlight[issuer] { return try await pending.value }
        let task = Task {
            let fresh = try await register(issuer)
            return OAuthClientCredentials(issuer: issuer, clientID: fresh.clientID, clientSecret: fresh.clientSecret)
        }
        inFlight[issuer] = task
        defer { inFlight[issuer] = nil }
        let bound = try await task.value
        stored[issuer] = bound
        return bound
    }
}

/// Client ID Metadata Documents: the `client_id` is an HTTPS URL that hosts the client's metadata.
public enum ClientIDMetadataDocument {
    /// A `client_id` is usable as a metadata document URL if it is an `https` URL with a path and no fragment.
    public static func validateClientID(_ clientID: String) throws -> URL {
        guard let url = URL(string: clientID), url.scheme == "https", url.host != nil,
              url.path.count > 1, url.fragment == nil else {
            throw OAuthConformanceError.invalidClientIDMetadataDocument("client_id must be an https URL with a path")
        }
        return url
    }

    /// Validate a fetched document: `client_id` must equal its URL; `client_name` and `redirect_uris` must be present.
    public static func validate(document: Data, fetchedFrom clientID: String) throws {
        _ = try validateClientID(clientID)
        guard let json = try? JSONSerialization.jsonObject(with: document) as? [String: Any] else {
            throw OAuthConformanceError.invalidClientIDMetadataDocument("not a JSON object")
        }
        guard json["client_id"] as? String == clientID else {
            throw OAuthConformanceError.invalidClientIDMetadataDocument("client_id does not match document URL")
        }
        guard let name = json["client_name"] as? String,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw OAuthConformanceError.invalidClientIDMetadataDocument("client_name is required")
        }
        guard let redirects = json["redirect_uris"] as? [String], !redirects.isEmpty else {
            throw OAuthConformanceError.invalidClientIDMetadataDocument("redirect_uris is required")
        }
    }
}

/// How a client should identify itself to an authorization server.
public enum OAuthClientRegistrationMethod: Equatable, Sendable {
    /// Use a Client ID Metadata Document URL as `client_id` (preferred).
    case clientIDMetadataDocument
    /// Fall back to dynamic client registration (deprecated in favor of CIMD).
    case dynamicRegistration
    case unavailable

    public static func select(
        clientIDMetadataDocumentSupported: Bool,
        registrationEndpoint: String?
    ) -> OAuthClientRegistrationMethod {
        if clientIDMetadataDocumentSupported { return .clientIDMetadataDocument }
        return registrationEndpoint != nil ? .dynamicRegistration : .unavailable
    }
}
#endif
