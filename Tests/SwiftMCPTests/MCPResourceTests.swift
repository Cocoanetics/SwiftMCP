import XCTest
import SwiftMCP
@testable import SwiftMCPMacros

// Define the enum for temperature settings
public enum Temp: String, CaseIterable, Sendable {
    case warm
    case hot
    case cold
}

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

    /// Gets a temperature status based on an enum parameter
    /// - Parameter status_value: The temperature setting (e.g., warm, hot, cold)
    /// - Returns: A string describing the temperature status
	@MCPResource("test://temperature/{status}")
	func getTemperatureStatus(status: Temp) -> String {
		switch status {
			case .warm:
				return "The temperature is pleasantly warm."
			case .hot:
				return "It's quite hot!"
			case .cold:
				return "Brrr, it's cold."
		}
	}
	
	/// Test resource with multiple URI templates
	@MCPResource(["api://v1/users/{user_id}", "api://v2/users/{user_id}"])
	func getMultiVersionUser(user_id: Int) -> String {
		return "User data for ID \(user_id)"
	}
}

final class MCPResourceTests: XCTestCase {
    
    func testResourceMetadata() {
        let server = ResourceTestServer()
        let metadata = server.mcpResourceMetadata
        
        // Should have 6 resources: getConfig, getUserProfile, getLocalizedProfile, getFileList, getTemperatureStatus, getMultiVersionUser
        XCTAssertEqual(metadata.count, 6)
        
        // Test static resource metadata
        let configMeta = metadata.first { $0.name == "getConfig" }
        XCTAssertNotNil(configMeta)
        XCTAssertTrue(configMeta?.uriTemplates.contains("config://app") ?? false)
        XCTAssertEqual(configMeta?.parameters.count, 0)
        
        // Test parameterized resource metadata
        let profileMeta = metadata.first { $0.name == "getUserProfile" }
        XCTAssertNotNil(profileMeta)
        XCTAssertTrue(profileMeta?.uriTemplates.contains("users://{user_id}/profile") ?? false)
        XCTAssertEqual(profileMeta?.parameters.count, 1)
        XCTAssertEqual(profileMeta?.parameters.first?.name, "user_id")
        
        // Test resource with optional parameter
        let localizedMeta = metadata.first { $0.name == "getLocalizedProfile" }
        XCTAssertNotNil(localizedMeta)
        XCTAssertTrue(localizedMeta?.uriTemplates.contains("users://{user_id}/profile/localized?locale={lang}") ?? false)
        XCTAssertEqual(localizedMeta?.parameters.count, 2)
        XCTAssertTrue(localizedMeta?.parameters.first { $0.name == "lang" }?.isOptional ?? false)
        
        // Test enum parameter resource
        let tempMeta = metadata.first { $0.name == "getTemperatureStatus" }
        XCTAssertNotNil(tempMeta)
        XCTAssertTrue(tempMeta?.uriTemplates.contains("test://temperature/{status}") ?? false)
        XCTAssertEqual(tempMeta?.parameters.count, 1)
        XCTAssertEqual(tempMeta?.parameters.first?.name, "status")
        
        // Test multiple URI templates resource
        let multiMeta = metadata.first { $0.name == "getMultiVersionUser" }
        XCTAssertNotNil(multiMeta)
        XCTAssertTrue(multiMeta?.uriTemplates.contains("api://v1/users/{user_id}") ?? false)
        XCTAssertTrue(multiMeta?.uriTemplates.contains("api://v2/users/{user_id}") ?? false)
        XCTAssertEqual(multiMeta?.uriTemplates.count, 2)
        XCTAssertEqual(multiMeta?.parameters.count, 1)
        XCTAssertEqual(multiMeta?.parameters.first?.name, "user_id")
    }
    
    func testResourceTemplates() async throws {
        let server = ResourceTestServer()
        
        let templates = await server.mcpResourceTemplates
        // users://{user_id}/profile
        // users://{user_id}/profile/localized?locale={lang}
        // test://temperature/{status}
        // api://v1/users/{user_id}
        // api://v2/users/{user_id}
        XCTAssertEqual(templates.count, 5) // Updated count
        
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

    func testResourceWithEnumParameter() async throws {
        let server = ResourceTestServer()

        // Test with 'warm'
        let warmURL = URL(string: "test://temperature/warm")!
        let warmResources = try await server.getResource(uri: warmURL)
        XCTAssertEqual(warmResources.count, 1)
        XCTAssertEqual(warmResources.first?.text, "The temperature is pleasantly warm.")

        // Test with 'hot'
        let hotURL = URL(string: "test://temperature/hot")!
        let hotResources = try await server.getResource(uri: hotURL)
        XCTAssertEqual(hotResources.count, 1)
        XCTAssertEqual(hotResources.first?.text, "It's quite hot!")

        // Test with 'cold'
        let coldURL = URL(string: "test://temperature/cold")!
        let coldResources = try await server.getResource(uri: coldURL)
        XCTAssertEqual(coldResources.count, 1)
        XCTAssertEqual(coldResources.first?.text, "Brrr, it's cold.")

        // Test with an invalid enum string value
        let invalidEnumURL = URL(string: "test://temperature/freezing")!
        do {
            _ = try await server.getResource(uri: invalidEnumURL)
            XCTFail("Should have thrown error for invalid enum value")
        } catch MCPToolError.invalidEnumValue(let parameterName, _, let actualValue) {
            // This is the expected error from extractValue for enums if the string doesn't match a case
            XCTAssertEqual(parameterName, "status")
            XCTAssertEqual(actualValue, "freezing")
        } catch {
            XCTFail("Wrong error type for invalid enum value: \(error)")
        }
    }
    
    func testURLTemplateExtraction() {
        // Test path variables
        let url1 = URL(string: "users://123/profile")!
        let template1 = "users://{user_id}/profile"
        
        let vars1 = url1.extractTemplateVariables(from: template1)
        XCTAssertNotNil(vars1)
        XCTAssertEqual(vars1?["user_id"], "123")
        
        // Test with query parameters
        let url2 = URL(string: "users://456/profile/localized?locale=fr")!
        let template2 = "users://{user_id}/profile/localized?locale={lang}"
        let vars2 = url2.extractTemplateVariables(from: template2)
        XCTAssertNotNil(vars2)
        XCTAssertEqual(vars2?["user_id"], "456")
        XCTAssertEqual(vars2?["lang"], "fr")
    }
    
    func testMultipleURITemplates() async throws {
        let server = ResourceTestServer()
        
        // Test v1 API endpoint
        let v1URL = URL(string: "api://v1/users/123")!
        let v1Resources = try await server.getResource(uri: v1URL)
        
        XCTAssertEqual(v1Resources.count, 1)
        XCTAssertEqual(v1Resources.first?.text, "User data for ID 123")
        
        // Test v2 API endpoint (same function, different template)
        let v2URL = URL(string: "api://v2/users/456")!
        let v2Resources = try await server.getResource(uri: v2URL)
        
        XCTAssertEqual(v2Resources.count, 1)
        XCTAssertEqual(v2Resources.first?.text, "User data for ID 456")
    }
} 
