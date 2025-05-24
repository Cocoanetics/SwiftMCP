import XCTest
import SwiftMCP
@testable import SwiftMCPMacros

/// Test server with resource functions
@MCPServer(name: "ResourceTestServer", version: "1.0")
actor ResourceTestServer {
    
    /// Gets a static configuration resource
    @MCPResource("config://app")
    func getConfig() -> String {
        return "App configuration here"
    }
    
    /// Gets a user profile by ID
    /// - Parameter user_id: The user's unique identifier
    /// - Returns: The user's profile data
    @MCPResource("users://{user_id}/profile")
    func getUserProfile(user_id: Int) -> String {
        return "Profile data for user \(user_id)"
    }
    
    /// Gets a user profile with locale
    /// - Parameters:
    ///   - user_id: The user's unique identifier
    ///   - lang: The language locale
    /// - Returns: Localized profile data
    @MCPResource("users://{user_id}/profile/localized?locale={lang}")
    func getLocalizedProfile(user_id: Int, lang: String = "en") -> String {
        return "Profile for user \(user_id) in \(lang)"
    }
    
    /// Gets multiple resources
    @MCPResource("files://list", mimeType: "application/json")
    func getFileList() -> [String] {
        return ["file1.txt", "file2.txt", "file3.txt"]
    }
}

final class MCPResourceTests: XCTestCase {
    
    func testResourceMetadata() async throws {
        let server = ResourceTestServer()
        
        // Check that server conforms to MCPResourceProviding
        XCTAssertTrue(server is MCPResourceProviding)
        
        // Get resource metadata
        let metadata = server.mcpResourceMetadata
        
        // Should have 4 resources
        XCTAssertEqual(metadata.count, 4)
        
        // Check getConfig metadata
        let configMeta = metadata.first { $0.name == "getConfig" }
        XCTAssertNotNil(configMeta)
        XCTAssertEqual(configMeta?.uriTemplate, "config://app")
        XCTAssertEqual(configMeta?.parameters.count, 0)
        
        // Check getUserProfile metadata
        let profileMeta = metadata.first { $0.name == "getUserProfile" }
        XCTAssertNotNil(profileMeta)
        XCTAssertEqual(profileMeta?.uriTemplate, "users://{user_id}/profile")
        XCTAssertEqual(profileMeta?.parameters.count, 1)
        XCTAssertEqual(profileMeta?.parameters.first?.name, "user_id")
        XCTAssertTrue(profileMeta?.parameters.first?.type == Int.self)
        
        // Check getLocalizedProfile metadata
        let localizedMeta = metadata.first { $0.name == "getLocalizedProfile" }
        XCTAssertNotNil(localizedMeta)
        XCTAssertEqual(localizedMeta?.uriTemplate, "users://{user_id}/profile/localized?locale={lang}")
        XCTAssertEqual(localizedMeta?.parameters.count, 2)
        XCTAssertTrue(localizedMeta?.parameters.first { $0.name == "lang" }?.isOptional ?? false)
    }
    
    func testResourceTemplates() async throws {
        let server = ResourceTestServer()
        
        let templates = await server.mcpResourceTemplates
        XCTAssertEqual(templates.count, 2)
        
        // Check that templates have correct structure
        for template in templates {
            XCTAssertFalse(template.uriTemplate.isEmpty)
            XCTAssertFalse(template.name.isEmpty)
        }
    }
    
    func testGetResourceStaticPath() async throws {
        let server = ResourceTestServer()
        
        // Test static resource
        let configURL = URL(string: "config://app")!
        let resources = try await server.getResource(uri: configURL)
        
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources.first?.text, "App configuration here")
    }
    
    func testGetResourceWithPathParameter() async throws {
        let server = ResourceTestServer()
        
        // Test resource with path parameter
        let profileURL = URL(string: "users://123/profile")!
        let resources = try await server.getResource(uri: profileURL)
        
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources.first?.text, "Profile data for user 123")
    }
    
    func testGetResourceWithOptionalParameter() async throws {
        let server = ResourceTestServer()
        
        // Test with default locale
        let defaultURL = URL(string: "users://456/profile/localized")!
        let defaultResources = try await server.getResource(uri: defaultURL)
        
        XCTAssertEqual(defaultResources.count, 1)
        XCTAssertEqual(defaultResources.first?.text, "Profile for user 456 in en")
        
        // Test with specified locale
        let localizedURL = URL(string: "users://456/profile/localized?locale=fr")!
        let localizedResources = try await server.getResource(uri: localizedURL)
        
        XCTAssertEqual(localizedResources.count, 1)
        XCTAssertEqual(localizedResources.first?.text, "Profile for user 456 in fr")
    }
    
    func testGetResourceNotFound() async throws {
        let server = ResourceTestServer()
        
        let invalidURL = URL(string: "users://invalid/path")!
        
        do {
            _ = try await server.getResource(uri: invalidURL)
            XCTFail("Should have thrown error")
        } catch let error as MCPResourceError {
            switch error {
            case .notFound(let uri):
                XCTAssertEqual(uri, invalidURL.absoluteString)
            default:
                XCTFail("Wrong error type: \(error)")
            }
        }
    }
    
    func testArrayReturnType() async throws {
        let server = ResourceTestServer()
        
        let filesURL = URL(string: "files://list")!
        let resources = try await server.getResource(uri: filesURL)
        
        XCTAssertEqual(resources.count, 1)
        XCTAssertNotNil(resources.first?.text)
        XCTAssertEqual(resources.first?.mimeType, "application/json")
        
        // The text should contain the array representation
        let text = resources.first?.text ?? ""
        XCTAssertTrue(text.contains("file1.txt"))
        XCTAssertTrue(text.contains("file2.txt"))
        XCTAssertTrue(text.contains("file3.txt"))
    }
    
    func testURLTemplateExtraction() {
        // Test path variables
        let url1 = URL(string: "users://123/profile")!
        let template1 = "users://{user_id}/profile"
        
        print("URL1 scheme: \(url1.scheme ?? "nil")")
        print("URL1 host: \(url1.host ?? "nil")")
        print("URL1 path: \(url1.path)")
        print("URL1 absoluteString: \(url1.absoluteString)")
        
        if let templateURL1 = URL(string: template1) {
            print("Template1 scheme: \(templateURL1.scheme ?? "nil")")
            print("Template1 host: \(templateURL1.host ?? "nil")")
            print("Template1 path: \(templateURL1.path)")
        } else {
            print("Failed to create URL from template: \(template1)")
        }
        
        let vars1 = url1.extractTemplateVariables(from: template1)
        print("Template: \(template1)")
        print("URL: \(url1)")
        print("Variables: \(String(describing: vars1))")
        XCTAssertNotNil(vars1)
        XCTAssertEqual(vars1?["user_id"], "123")
        
        // Test with query parameters
        let url2 = URL(string: "users://456/profile/localized?locale=fr")!
        let template2 = "users://{user_id}/profile/localized?locale={lang}"
        let vars2 = url2.extractTemplateVariables(from: template2)
        print("Template: \(template2)")
        print("URL: \(url2)")
        print("Variables: \(String(describing: vars2))")
        XCTAssertNotNil(vars2)
        XCTAssertEqual(vars2?["user_id"], "456")
        XCTAssertEqual(vars2?["lang"], "fr")
    }
} 