import Foundation
import Testing
import SwiftMCP

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

@Suite("MCP Resource Tests", .tags(.unit))
struct MCPResourceTests {
    @Test("Resource metadata includes generated values")
    func resourceMetadata() {
        let server = ResourceTestServer()
        let metadata = server.mcpResourceMetadata

        // Should have 6 resources: getConfig, getUserProfile, getLocalizedProfile, getFileList, getTemperatureStatus, getMultiVersionUser
        #expect(metadata.count == 6)

        // Test static resource metadata
        let configMeta = metadata.first { $0.name == "getConfig" }
        #expect(configMeta != nil)
        #expect(configMeta?.uriTemplates.contains("config://app") == true)
        #expect(configMeta?.parameters.count == 0)

        // Test parameterized resource metadata
        let profileMeta = metadata.first { $0.name == "getUserProfile" }
        #expect(profileMeta != nil)
        #expect(profileMeta?.uriTemplates.contains("users://{user_id}/profile") == true)
        #expect(profileMeta?.parameters.count == 1)
        #expect(profileMeta?.parameters.first?.name == "user_id")

        // Test resource with optional parameter
        let localizedMeta = metadata.first { $0.name == "getLocalizedProfile" }
        #expect(localizedMeta != nil)
        #expect(localizedMeta?.uriTemplates.contains("users://{user_id}/profile/localized?locale={lang}") == true)
        #expect(localizedMeta?.parameters.count == 2)
        #expect(localizedMeta?.parameters.first(where: { $0.name == "lang" })?.isOptional == true)

        // Test enum parameter resource
        let tempMeta = metadata.first { $0.name == "getTemperatureStatus" }
        #expect(tempMeta != nil)
        #expect(tempMeta?.uriTemplates.contains("test://temperature/{status}") == true)
        #expect(tempMeta?.parameters.count == 1)
        #expect(tempMeta?.parameters.first?.name == "status")

        // Test multiple URI templates resource
        let multiMeta = metadata.first { $0.name == "getMultiVersionUser" }
        #expect(multiMeta != nil)
        #expect(multiMeta?.uriTemplates.contains("api://v1/users/{user_id}") == true)
        #expect(multiMeta?.uriTemplates.contains("api://v2/users/{user_id}") == true)
        #expect(multiMeta?.uriTemplates.count == 2)
        #expect(multiMeta?.parameters.count == 1)
        #expect(multiMeta?.parameters.first?.name == "user_id")
    }

    @Test("Resource templates reflect annotations")
    func resourceTemplates() async throws {
        let server = ResourceTestServer()

        let templates = await server.mcpResourceTemplates
        // users://{user_id}/profile
        // users://{user_id}/profile/localized?locale={lang}
        // test://temperature/{status}
        // api://v1/users/{user_id}
        // api://v2/users/{user_id}
        #expect(templates.count == 5)

        // Check that templates have correct structure
        for template in templates {
            #expect(!template.uriTemplate.isEmpty)
            #expect(!template.name.isEmpty)
        }
    }

    @Test("Static resource can be fetched")
    func getResourceStaticPath() async throws {
        let server = ResourceTestServer()

        let configURL = URL(string: "config://app")!
        let resources = try await server.getResource(uri: configURL)

        #expect(resources.count == 1)
        #expect(resources.first?.text == "App configuration here")
    }

    @Test("Resource supports path parameters")
    func getResourceWithPathParameter() async throws {
        let server = ResourceTestServer()

        let profileURL = URL(string: "users://123/profile")!
        let resources = try await server.getResource(uri: profileURL)

        #expect(resources.count == 1)
        #expect(resources.first?.text == "Profile data for user 123")
    }

    @Test("Optional parameters are parsed")
    func getResourceWithOptionalParameter() async throws {
        let server = ResourceTestServer()

        let defaultURL = URL(string: "users://456/profile/localized")!
        let defaultResources = try await server.getResource(uri: defaultURL)

        #expect(defaultResources.count == 1)
        #expect(defaultResources.first?.text == "Profile for user 456 in en")

        let localizedURL = URL(string: "users://456/profile/localized?locale=fr")!
        let localizedResources = try await server.getResource(uri: localizedURL)

        #expect(localizedResources.count == 1)
        #expect(localizedResources.first?.text == "Profile for user 456 in fr")
    }

    @Test("Missing resources surface notFound errors")
    func getResourceNotFound() async {
        let server = ResourceTestServer()

        let invalidURL = URL(string: "users://invalid/path")!

        do {
            _ = try await server.getResource(uri: invalidURL)
            Issue.record("Expected MCPResourceError.notFound")
        } catch MCPResourceError.notFound(let uri) {
            #expect(uri == invalidURL.absoluteString)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Array return types convert to MCPResource")
    func arrayReturnType() async throws {
        let server = ResourceTestServer()

        let filesURL = URL(string: "files://list")!
        let resources = try await server.getResource(uri: filesURL)

        #expect(resources.count == 1)
        #expect(resources.first?.text != nil)
        #expect(resources.first?.mimeType == "application/json")

        let text = resources.first?.text ?? ""
        #expect(text.contains("file1.txt"))
        #expect(text.contains("file2.txt"))
        #expect(text.contains("file3.txt"))
    }

    @Test("Enum parameters decode correctly")
    func resourceWithEnumParameter() async throws {
        let server = ResourceTestServer()

        let warmURL = URL(string: "test://temperature/warm")!
        let warmResources = try await server.getResource(uri: warmURL)
        #expect(warmResources.count == 1)
        #expect(warmResources.first?.text == "The temperature is pleasantly warm.")

        let hotURL = URL(string: "test://temperature/hot")!
        let hotResources = try await server.getResource(uri: hotURL)
        #expect(hotResources.count == 1)
        #expect(hotResources.first?.text == "It's quite hot!")

        let coldURL = URL(string: "test://temperature/cold")!
        let coldResources = try await server.getResource(uri: coldURL)
        #expect(coldResources.count == 1)
        #expect(coldResources.first?.text == "Brrr, it's cold.")

        let invalidEnumURL = URL(string: "test://temperature/freezing")!
        do {
            _ = try await server.getResource(uri: invalidEnumURL)
            Issue.record("Should have thrown error for invalid enum value")
        } catch MCPToolError.invalidEnumValue(let parameterName, _, let actualValue) {
            #expect(parameterName == "status")
            #expect(actualValue == "freezing")
        } catch {
            Issue.record("Wrong error type for invalid enum value: \(error)")
        }
    }

    @Test("URI template extraction resolves variables")
    func urlTemplateExtraction() {
        let url1 = URL(string: "users://123/profile")!
        let template1 = "users://{user_id}/profile"

        let vars1 = url1.extractTemplateVariables(from: template1)
        #expect(vars1 != nil)
        #expect(vars1?["user_id"] == "123")

        let url2 = URL(string: "users://456/profile/localized?locale=fr")!
        let template2 = "users://{user_id}/profile/localized?locale={lang}"
        let vars2 = url2.extractTemplateVariables(from: template2)
        #expect(vars2 != nil)
        #expect(vars2?["user_id"] == "456")
        #expect(vars2?["lang"] == "fr")
    }

    @Test("Multiple URI templates resolve to same resource")
    func multipleURITemplates() async throws {
        let server = ResourceTestServer()

        let v1URL = URL(string: "api://v1/users/123")!
        let v1Resources = try await server.getResource(uri: v1URL)

        #expect(v1Resources.count == 1)
        #expect(v1Resources.first?.text == "User data for ID 123")

        let v2URL = URL(string: "api://v2/users/456")!
        let v2Resources = try await server.getResource(uri: v2URL)

        #expect(v2Resources.count == 1)
        #expect(v2Resources.first?.text == "User data for ID 456")
    }
}
