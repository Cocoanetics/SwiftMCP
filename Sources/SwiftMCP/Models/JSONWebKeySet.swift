import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// JSON Web Key Set (JWKS) for signature verification
public struct JSONWebKeySet: Codable, Sendable {
    public let keys: [JSONWebKey]
    
    public init(keys: [JSONWebKey]) {
        self.keys = keys
    }
    
    /// Initialize JSONWebKeySet by fetching from an issuer
    /// - Parameter issuer: The JWT issuer
    /// - Throws: JWTError if fetch fails
    public init(fromIssuer issuer: String) async throws {
        let jwksURL = "\(issuer).well-known/jwks.json"
        
        guard let url = URL(string: jwksURL) else {
            throw JWTError.jwksFetchFailed
        }
        
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