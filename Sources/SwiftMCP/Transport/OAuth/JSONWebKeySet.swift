import Foundation
import Crypto
import _CryptoExtras
import X509
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// JWKS cache manager to avoid repeated HTTP requests for the same issuer
/// 
/// This actor provides thread-safe caching of JSON Web Key Sets (JWKS) to improve
/// performance by avoiding redundant HTTP requests when validating multiple JWT tokens
/// from the same issuer.
public actor JWKSCache {
    /// Internal cache storage mapping issuer URLs to cached JWKS and timestamp
    private var cache: [URL: (JSONWebKeySet, Date)] = [:]
    
    /// How long to keep JWKS in cache before refetching (in seconds)
    private let cacheValidityDuration: TimeInterval
    
    /// Initialize a JWKS cache with custom validity duration
    /// - Parameter cacheValidityDuration: How long to cache JWKS (default: 1 hour)
    public init(cacheValidityDuration: TimeInterval = 3600) { // Default 1 hour
        self.cacheValidityDuration = cacheValidityDuration
    }
    
    /// Shared global JWKS cache instance for use across the application
    /// 
    /// Use this shared instance when you want to share JWKS cache across different
    /// parts of your application to maximize cache efficiency.
    public static let shared = JWKSCache()
    
    /// Get JWKS for an issuer, using cache if available and valid
    /// 
    /// This method first checks if a valid cached JWKS exists for the issuer.
    /// If found and not expired, it returns the cached version. Otherwise,
    /// it fetches a fresh JWKS from the issuer's `.well-known/jwks.json` endpoint.
    /// 
    /// - Parameter issuer: The JWT issuer URL
    /// - Returns: Cached JWKS or fetches new one
    /// - Throws: JWTError if fetch fails
    /// 
    /// ## Usage Example
    /// ```swift
    /// // Use shared cache (recommended for most cases)
    /// let jwks = try await JWKSCache.shared.getJWKS(for: issuerURL)
    /// 
    /// // Or create a custom cache with different TTL
    /// let cache = JWKSCache(cacheValidityDuration: 1800) // 30 minutes
    /// let jwks = try await cache.getJWKS(for: issuerURL)
    /// ```
    func getJWKS(for issuer: URL) async throws -> JSONWebKeySet {
        let now = Date()
        
        // Check if we have a valid cached entry
        if let (jwks, cachedAt) = cache[issuer],
           now.timeIntervalSince(cachedAt) < cacheValidityDuration {
            return jwks
        }
        
        // Fetch new JWKS
        let jwks = try await JSONWebKeySet(fromIssuer: issuer)
        cache[issuer] = (jwks, now)
        return jwks
    }
    
    /// Clear all cached JWKS entries
    /// 
    /// Use this method to force fresh JWKS fetches on the next request.
    func clearCache() {
        cache.removeAll()
    }
    
    /// Remove a specific issuer from cache
    /// 
    /// Use this method to force a fresh JWKS fetch for a specific issuer
    /// while keeping other cached entries intact.
    /// 
    /// - Parameter issuer: The issuer to remove from cache
    func removeFromCache(issuer: URL) {
        cache.removeValue(forKey: issuer)
    }
}

/// JSON Web Key Set (JWKS) for signature verification according to RFC 7517
/// 
/// A JWKS is a set of keys containing the public keys that should be used to verify
/// any JWT issued by the authorization server. This structure represents the response
/// from a `.well-known/jwks.json` endpoint.
public struct JSONWebKeySet: Codable, Sendable {
    /// Array of JSON Web Keys in this set
    public let keys: [JSONWebKey]
    
    /// Initialize a JSON Web Key Set
    /// - Parameter keys: Array of JSON Web Keys
    public init(keys: [JSONWebKey]) {
        self.keys = keys
    }
    
    /// Get a public key by key ID
    /// 
    /// This method searches through the JWKS to find a key with the specified `kid`
    /// and creates an RSA public key from it. It supports both X.509 certificate-based
    /// and raw RSA parameter-based keys.
    /// 
    /// - Parameter kid: The key ID to look up
    /// - Returns: RSA public key if found and valid, nil otherwise
    public func key(kid: String) -> _RSA.Signing.PublicKey? {
        guard let jwk = keys.first(where: { $0.kid == kid }) else {
            return nil
        }
        
        return try? jwk.createRSAPublicKey()
    }
    
    /// Initialize JSONWebKeySet by fetching from an issuer
    /// 
    /// This initializer fetches the JWKS from the issuer's `.well-known/jwks.json`
    /// endpoint. It constructs the URL by appending `.well-known/jwks.json` to the
    /// issuer URL and performs an HTTP GET request.
    /// 
    /// - Parameter issuer: The JWT issuer URL
    /// - Throws: JWTError if fetch fails
    public init(fromIssuer issuer: URL) async throws {
        let url = issuer.appendingPathComponent(".well-known/jwks.json")
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw JWTError.jwksFetchFailed
        }
        
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .secondsSince1970
            let jwks = try decoder.decode(JSONWebKeySet.self, from: data)
            self = jwks
        } catch {
            throw JWTError.jwksFetchFailed
        }
    }
} 