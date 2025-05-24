import SwiftMCP
import Foundation

/// A demo server showcasing MCP Resources functionality
@MCPServer(name: "DemoResourceServer", version: "1.0")
actor DemoResourceServer {
    
    // MARK: - Basic Resources
    
    /// Get server information as a static resource
    @MCPResource("server://info")
    func getServerInfo() -> String {
        return """
        Server: DemoResourceServer v1.0
        Status: Running
        Resources: Available
        """
    }
    
    // MARK: - Path Parameters
    
    /// Get user information by ID
    /// - Parameter user_id: The user's unique identifier  
    /// - Returns: User information in JSON format
    @MCPResource("users://profile/{user_id}", mimeType: "application/json")
    func getUser(user_id: Int) -> String {
        // In a real implementation, this would fetch from a database
        return """
        {
            "id": \(user_id),
            "name": "User \(user_id)",
            "email": "user\(user_id)@example.com"
        }
        """
    }
    
    /// Get a specific post for a user
    /// - Parameters:
    ///   - user_id: The user's unique identifier
    ///   - post_id: The post's unique identifier
    /// - Returns: Post content
    @MCPResource("users://{user_id}/posts/{post_id}")
    func getUserPost(user_id: Int, post_id: Int) -> String {
        return "Post #\(post_id) by User #\(user_id): Lorem ipsum dolor sit amet..."
    }
    
    // MARK: - Query Parameters with Defaults
    
    /// Search for users with pagination
    /// - Parameters:
    ///   - query: Search query string
    ///   - page: Page number (1-based)
    ///   - limit: Number of results per page
    /// - Returns: Search results in JSON format
    @MCPResource("users://search?q={query}&page={page}&limit={limit}", mimeType: "application/json")
    func searchUsers(query: String, page: Int = 1, limit: Int = 10) -> String {
        return """
        {
            "query": "\(query)",
            "page": \(page),
            "limit": \(limit),
            "results": [
                {"id": 1, "name": "John Doe"},
                {"id": 2, "name": "Jane Smith"}
            ],
            "total": 2
        }
        """
    }
    
    /// Get localized content
    /// - Parameters:
    ///   - content_id: The content identifier
    ///   - lang: Language code (ISO 639-1)
    ///   - region: Region code (optional)
    /// - Returns: Localized content
    @MCPResource("content://{content_id}/localized?lang={lang}&region={region}")
    func getLocalizedContent(content_id: String, lang: String = "en", region: String = "US") -> String {
        return "Content '\(content_id)' in \(lang)-\(region): Welcome!"
    }
    
    // MARK: - Different Return Types
    
    /// Get system metrics
    /// - Returns: Array of metric values
    @MCPResource("metrics://system")
    func getSystemMetrics() -> [Double] {
        // Simulated metrics
        return [0.75, 0.82, 0.91, 0.68, 0.79]
    }
    
    /// Check if a feature is enabled
    /// - Parameter feature_name: Name of the feature to check
    /// - Returns: Whether the feature is enabled
    @MCPResource("features://{feature_name}/enabled")
    func isFeatureEnabled(feature_name: String) -> Bool {
        // Simulated feature flags
        let enabledFeatures = ["dark_mode", "beta_ui", "advanced_search"]
        return enabledFeatures.contains(feature_name.lowercased())
    }
    
    // MARK: - Complex Types
    
    struct ConfigData: Codable {
        let theme: String
        let maxUploadSize: Int
        let features: [String]
    }
    
    /// Get application configuration
    /// - Parameter env: Environment (dev, staging, prod)
    /// - Returns: Configuration data
    @MCPResource("config://{env}", mimeType: "application/json")
    func getConfig(env: String = "prod") -> ConfigData {
        switch env {
        case "dev":
            return ConfigData(
                theme: "debug",
                maxUploadSize: 100_000_000,
                features: ["debug_panel", "verbose_logging"]
            )
        case "staging":
            return ConfigData(
                theme: "default",
                maxUploadSize: 50_000_000,
                features: ["beta_features"]
            )
        default:
            return ConfigData(
                theme: "default", 
                maxUploadSize: 10_000_000,
                features: ["stable_features"]
            )
        }
    }
    
    // MARK: - Error Handling
    
    /// Get sensitive data (throws if unauthorized)
    /// - Parameter key: The data key
    /// - Returns: The sensitive data
    /// - Throws: Error if access is denied
    @MCPResource("secure://{key}")
    func getSecureData(key: String) throws -> String {
        // Simulated access control
        let publicKeys = ["public_info", "terms_of_service"]
        guard publicKeys.contains(key) else {
            throw ResourceError.accessDenied(key: key)
        }
        return "Data for key '\(key)': [REDACTED]"
    }
}

// Custom error type
enum ResourceError: Error, LocalizedError {
    case accessDenied(key: String)
    
    var errorDescription: String? {
        switch self {
        case .accessDenied(let key):
            return "Access denied for key: \(key)"
        }
    }
}

// MARK: - Usage Example

@main
struct ResourceDemoApp {
    static func main() async throws {
        let server = DemoResourceServer()
        
        print("=== MCP Resource Demo ===\n")
        
        // Print available resources
        print("Available Resources:")
        for template in await server.mcpResourceTemplates {
            print("- \(template.name): \(template.uriTemplate)")
            if let desc = template.description {
                print("  Description: \(desc)")
            }
        }
        
        print("\n=== Testing Resources ===\n")
        
        // Test static resource
        print("1. Static Resource:")
        let infoURL = URL(string: "server://info")!
        let info = try await server.getResource(uri: infoURL)
        print("Response: \(info.first?.text ?? "N/A")\n")
        
        // Test path parameter
        print("2. Path Parameter:")
        let userURL = URL(string: "users://profile/42")!
        let user = try await server.getResource(uri: userURL)
        print("Response: \(user.first?.text ?? "N/A")\n")
        
        // Test query parameters with defaults
        print("3. Query Parameters (using defaults):")
        let searchURL1 = URL(string: "users://search?q=john")!
        let search1 = try await server.getResource(uri: searchURL1)
        print("Response: \(search1.first?.text ?? "N/A")\n")
        
        // Test query parameters with custom values
        print("4. Query Parameters (custom values):")
        let searchURL2 = URL(string: "users://search?q=jane&page=2&limit=20")!
        let search2 = try await server.getResource(uri: searchURL2)
        print("Response: \(search2.first?.text ?? "N/A")\n")
        
        // Test error handling
        print("5. Error Handling:")
        do {
            let secureURL = URL(string: "secure://private_key")!
            _ = try await server.getResource(uri: secureURL)
        } catch {
            print("Expected error: \(error.localizedDescription)\n")
        }
        
        // Test feature flags
        print("6. Boolean Return Type:")
        let featureURL = URL(string: "features://dark_mode/enabled")!
        let feature = try await server.getResource(uri: featureURL)
        print("Dark mode enabled: \(feature.first?.text ?? "N/A")\n")
        
        print("=== Demo Complete ===")
    }
} 