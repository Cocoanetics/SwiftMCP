import Testing
import Foundation
@testable import SwiftMCP

@MCPServer(name: "OpenAPITestServer", version: "1.0")
class OpenAPITestServer {
    
    /// A test tool
    @MCPTool
    func testTool(message: String) -> String {
        return "Tool: \(message)"
    }
    
    @MCPResource("api://test/{id}")
    func testResource(id: Int) -> String {
        return "Resource: \(id)"
    }
}

@Suite("OpenAPI Resource Tests", .tags(.openAPI, .unit))
struct OpenAPIResourceTests {
    
    @Test("OpenAPI spec includes both tools and resources")
    func openAPISpecIncludesBothToolsAndResources() throws {
        let server = OpenAPITestServer()
        let spec = OpenAPISpec(server: server, scheme: "https", host: "example.com")
        

        // Should have 2 paths: one for the tool and one for the resource
        #expect(spec.paths.count == 2)
        
        // Check that both tool and resource are included
        let pathKeys = Set(spec.paths.keys)
        #expect(pathKeys.contains("/openapitestserver/testTool"))
        #expect(pathKeys.contains("/openapitestserver/testResource"))
        
        // Verify both have POST operations
        #expect(spec.paths["/openapitestserver/testTool"]?.post != nil)
        #expect(spec.paths["/openapitestserver/testResource"]?.post != nil)
        
        // Verify the resource function has the correct parameter
        let resourceOperation = spec.paths["/openapitestserver/testResource"]?.post
        #expect(resourceOperation?.requestBody != nil)
        
        // The resource should have an 'id' parameter
        if case let .object(inputSchema) = resourceOperation?.requestBody?.content["application/json"]?.schema {
            #expect(inputSchema.properties.keys.contains("id"))
            #expect(inputSchema.required.contains("id"))
        } else {
            throw TestError("Expected object schema for resource input")
        }
    }
    
    @Test("Resource function can be called via HTTP handler")
    func resourceFunctionCanBeCalledViaHTTPHandler() async throws {
        let server = OpenAPITestServer()
        
        // Test that the resource function can be called as a function
        let result = try await server.callResourceAsFunction("testResource", arguments: ["id": 42])
        
        // Should return the resource content
        #expect(result is String || result is [GenericResourceContent])
        
        if let stringResult = result as? String {
            #expect(stringResult == "Resource: 42")
        } else if let resourceArray = result as? [GenericResourceContent] {
            #expect(resourceArray.count == 1)
            #expect(resourceArray.first?.text == "Resource: 42")
        } else {
            throw TestError("Unexpected result type: \(type(of: result))")
        }
    }
}

// MARK: - Test Tags Extension
extension Tag {
    @Tag static var openAPI: Self
} 
