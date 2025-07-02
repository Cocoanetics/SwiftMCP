import Foundation
import Crypto
import _CryptoExtras
import X509
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// JWKS cache manager to avoid repeated HTTP requests
public actor JWKSCache {
    private var cache: [URL: (JSONWebKeySet, Date)] = [:]
    private let cacheValidityDuration: TimeInterval
    
    public init(cacheValidityDuration: TimeInterval = 3600) { // Default 1 hour
        self.cacheValidityDuration = cacheValidityDuration
    }
    
    /// Shared global JWKS cache instance
    public static let shared = JWKSCache()
    
    /// Get JWKS for an issuer, using cache if available and valid
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
    
    /// Clear the cache
    func clearCache() {
        cache.removeAll()
    }
    
    /// Remove a specific issuer from cache
    /// - Parameter issuer: The issuer to remove
    func removeFromCache(issuer: URL) {
        cache.removeValue(forKey: issuer)
    }
}

/// JSON Web Key Set (JWKS) for signature verification
public struct JSONWebKeySet: Codable, Sendable {
    public let keys: [JSONWebKey]
    
    public init(keys: [JSONWebKey]) {
        self.keys = keys
    }
    
    /// Get a public key by key ID
    /// - Parameter kid: The key ID to look up
    /// - Returns: RSA public key if found and valid, nil otherwise
    public func key(kid: String) -> _RSA.Signing.PublicKey? {
        guard let jwk = keys.first(where: { $0.kid == kid }) else {
            return nil
        }
        
        return try? jwk.createRSAPublicKey()
    }
    
    /// Initialize JSONWebKeySet by fetching from an issuer
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