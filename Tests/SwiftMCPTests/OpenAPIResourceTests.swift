import XCTest
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

final class OpenAPIResourceTests: XCTestCase {
    
    func testOpenAPISpecIncludesBothToolsAndResources() throws {
        let server = OpenAPITestServer()
        let spec = OpenAPISpec(server: server, scheme: "https", host: "example.com")
        

        // Should have 2 paths: one for the tool and one for the resource
        XCTAssertEqual(spec.paths.count, 2)
        
        // Check that both tool and resource are included
        let pathKeys = Set(spec.paths.keys)
        XCTAssertTrue(pathKeys.contains("/openapitestserver/testTool"))
        XCTAssertTrue(pathKeys.contains("/openapitestserver/testResource"))
        
        // Verify both have POST operations
        XCTAssertNotNil(spec.paths["/openapitestserver/testTool"]?.post)
        XCTAssertNotNil(spec.paths["/openapitestserver/testResource"]?.post)
        
        // Verify the resource function has the correct parameter
        let resourceOperation = spec.paths["/openapitestserver/testResource"]?.post
        XCTAssertNotNil(resourceOperation?.requestBody)
        
        // The resource should have an 'id' parameter
        if case let .object(inputSchema) = resourceOperation?.requestBody?.content["application/json"]?.schema {
            XCTAssertTrue(inputSchema.properties.keys.contains("id"))
            XCTAssertTrue(inputSchema.required.contains("id"))
        } else {
            XCTFail("Expected object schema for resource input")
        }
    }
    
    func testResourceFunctionCanBeCalledViaHTTPHandler() async throws {
        let server = OpenAPITestServer()
        
        // Test that the resource function can be called as a function
        let result = try await server.callResourceAsFunction("testResource", arguments: ["id": 42])
        
        // Should return the resource content
        XCTAssertTrue(result is String || result is [GenericResourceContent])
        
        if let stringResult = result as? String {
            XCTAssertEqual(stringResult, "Resource: 42")
        } else if let resourceArray = result as? [GenericResourceContent] {
            XCTAssertEqual(resourceArray.count, 1)
            XCTAssertEqual(resourceArray.first?.text, "Resource: 42")
        } else {
            XCTFail("Unexpected result type: \(type(of: result))")
        }
    }
} 
