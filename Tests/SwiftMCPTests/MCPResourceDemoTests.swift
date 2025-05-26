import XCTest
import SwiftMCP
@testable import SwiftMCPMacros

/// Test server demonstrating various @MCPResource use cases
@MCPServer(name: "DemoResourceServer", version: "1.0")
actor DemoResourceTestServer {
    
    /// Get server information as a static resource
    @MCPResource("server://info")
    func getServerInfo() -> String {
        return """
        Server: DemoResourceServer v1.0
        Status: Running
        Resources: Available
        """
    }
    
    /// Get user information by ID
    @MCPResource("users://profile/{user_id}", mimeType: "application/json")
    func getUser(user_id: Int) -> String {
        return """
        {
            "id": \(user_id),
            "name": "User \(user_id)",
            "email": "user\(user_id)@example.com"
        }
        """
    }
    
    /// Search for users with pagination
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
    
    /// Get system metrics
    @MCPResource("metrics://system")
    func getSystemMetrics() -> [Double] {
        return [0.75, 0.82, 0.91, 0.68, 0.79]
    }
    
    /// Check if a feature is enabled
    @MCPResource("features://{feature_name}/enabled")
    func isFeatureEnabled(feature_name: String) -> Bool {
        let enabledFeatures = ["dark_mode", "beta_ui", "advanced_search"]
        return enabledFeatures.contains(feature_name.lowercased())
    }
    
    struct ConfigData: Codable, CustomStringConvertible {
        let theme: String
        let maxUploadSize: Int
        let features: [String]
        
        var description: String {
            return "ConfigData(theme: \"\(theme)\", maxUploadSize: \(maxUploadSize), features: \(features))"
        }
    }
    
    /// Get application configuration
    @MCPResource("config://{env}", mimeType: "application/json")
    func getConfig(env: String = "prod") -> ConfigData {
        switch env {
        case "dev":
            return ConfigData(
                theme: "debug",
                maxUploadSize: 100_000_000,
                features: ["debug_panel", "verbose_logging"]
            )
        default:
            return ConfigData(
                theme: "default", 
                maxUploadSize: 10_000_000,
                features: ["stable_features"]
            )
        }
    }
}

final class MCPResourceDemoTests: XCTestCase {
    
    func testDemoResourceMetadata() async throws {
        let server = DemoResourceTestServer()
        let metadata = server.mcpResourceMetadata
        
        // Should have 6 resources
        XCTAssertEqual(metadata.count, 6)
        
        // Verify each resource is properly registered
        XCTAssertNotNil(metadata.first { $0.uriTemplates.contains("server://info") })
        XCTAssertNotNil(metadata.first { $0.uriTemplates.contains("users://profile/{user_id}") })
        XCTAssertNotNil(metadata.first { $0.uriTemplates.contains("users://search?q={query}&page={page}&limit={limit}") })
        XCTAssertNotNil(metadata.first { $0.uriTemplates.contains("metrics://system") })
        XCTAssertNotNil(metadata.first { $0.uriTemplates.contains("features://{feature_name}/enabled") })
        XCTAssertNotNil(metadata.first { $0.uriTemplates.contains("config://{env}") })
    }
    
    func testStaticResource() async throws {
        let server = DemoResourceTestServer()
        
        let infoURL = URL(string: "server://info")!
        let resources = try await server.getResource(uri: infoURL)
        
        XCTAssertEqual(resources.count, 1)
        XCTAssertTrue(resources.first?.text?.contains("DemoResourceServer v1.0") ?? false)
    }
    
    func testPathParameterResource() async throws {
        let server = DemoResourceTestServer()
        
        let userURL = URL(string: "users://profile/42")!
        let resources = try await server.getResource(uri: userURL)
        
        XCTAssertEqual(resources.count, 1)
        let text = resources.first?.text ?? ""
        XCTAssertTrue(text.contains("\"id\": 42"))
        XCTAssertTrue(text.contains("\"name\": \"User 42\""))
        XCTAssertEqual(resources.first?.mimeType, "application/json")
    }
    
    func testQueryParametersWithDefaults() async throws {
        let server = DemoResourceTestServer()
        
        // Test with only required parameter
        let searchURL1 = URL(string: "users://search?q=john")!
        let resources1 = try await server.getResource(uri: searchURL1)
        
        let text1 = resources1.first?.text ?? ""
        XCTAssertTrue(text1.contains("\"query\": \"john\""))
        XCTAssertTrue(text1.contains("\"page\": 1"))  // Default value
        XCTAssertTrue(text1.contains("\"limit\": 10")) // Default value
        
        // Test with all parameters
        let searchURL2 = URL(string: "users://search?q=jane&page=2&limit=20")!
        let resources2 = try await server.getResource(uri: searchURL2)
        
        let text2 = resources2.first?.text ?? ""
        XCTAssertTrue(text2.contains("\"query\": \"jane\""))
        XCTAssertTrue(text2.contains("\"page\": 2"))
        XCTAssertTrue(text2.contains("\"limit\": 20"))
    }
    
    func testArrayReturnType() async throws {
        let server = DemoResourceTestServer()
        
        let metricsURL = URL(string: "metrics://system")!
        let resources = try await server.getResource(uri: metricsURL)
        
        XCTAssertEqual(resources.count, 1)
        let text = resources.first?.text ?? ""
        
        // The array should be converted to string representation
        XCTAssertTrue(text.contains("0.75"))
        XCTAssertTrue(text.contains("0.82"))
        XCTAssertTrue(text.contains("0.91"))
    }
    
    func testBooleanReturnType() async throws {
        let server = DemoResourceTestServer()
        
        // Test enabled feature
        let darkModeURL = URL(string: "features://dark_mode/enabled")!
        let darkModeResources = try await server.getResource(uri: darkModeURL)
        XCTAssertEqual(darkModeResources.first?.text, "true")
        
        // Test disabled feature
        let unknownURL = URL(string: "features://unknown_feature/enabled")!
        let unknownResources = try await server.getResource(uri: unknownURL)
        XCTAssertEqual(unknownResources.first?.text, "false")
    }
    
    func testComplexReturnType() async throws {
        let server = DemoResourceTestServer()
        
        // Test with default environment
        let prodURL = URL(string: "config://prod")!
        let prodResources = try await server.getResource(uri: prodURL)
        
        let prodText = prodResources.first?.text ?? ""
        XCTAssertFalse(prodText.isEmpty, "Prod response text should not be empty")
        
        XCTAssertTrue(prodText.contains("\"theme\" : \"default\""), "Prod response should contain theme:default as JSON")
        XCTAssertTrue(prodText.contains("\"maxUploadSize\" : 10000000"), "Prod response should contain maxUploadSize as JSON")

        // Simplified assertion for prod features
        XCTAssertTrue(prodText.contains("stable_features"), "Prod response should contain 'stable_features'")

        // Test with dev environment
        let devURL = URL(string: "config://dev")!
        let devResources = try await server.getResource(uri: devURL)
        let devText = devResources.first?.text ?? ""
        XCTAssertFalse(devText.isEmpty, "Dev response text should not be empty")
        XCTAssertTrue(devText.contains("\"theme\" : \"debug\""), "Dev response should contain theme:debug as JSON")
        XCTAssertTrue(devText.contains("\"maxUploadSize\" : 100000000"), "Dev response should contain maxUploadSize as JSON")

        // Simplified assertion for dev features
        XCTAssertTrue(devText.contains("debug_panel"), "Dev response should contain 'debug_panel'")
    }
} 