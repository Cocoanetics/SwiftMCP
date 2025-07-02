import Foundation
import Crypto
import _CryptoExtras
import X509
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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
        
        #if canImport(FoundationNetworking)
        // For Linux/cross-platform environments, use FoundationNetworking
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                if let error = error {
                    continuation.resume(throwing: JWTError.jwksFetchFailed)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200,
                      let data = data else {
                    continuation.resume(throwing: JWTError.jwksFetchFailed)
                    return
                }
                
                continuation.resume(returning: data)
            }
            task.resume()
        }
        #else
        // For Darwin/macOS/iOS environments, use standard URLSession
        let (data, response) = try await URLSession.shared.data(from: url)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw JWTError.jwksFetchFailed
        }
        #endif
        
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