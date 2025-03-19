import Testing
@testable import SwiftMCP

@MCPServer(name: "test_server")
class TestAPIServer {
    /// A simple function that returns a string
    /// - Returns: A greeting message
    @MCPTool
    func simpleFunction() -> String {
        return "Hello"
    }
    
    /// A function that takes parameters and can throw
    /// - Parameters:
    ///   - name: The name to greet
    ///   - count: Number of times to repeat
    /// - Returns: A greeting message
    /// - Throws: If count is negative
    @MCPTool
    func throwingFunction(name: String, count: Int) throws -> String {
        if count < 0 {
            throw MCPToolError.invalidArgumentType(parameterName: "count", expectedType: "positive Int", actualValue: "\(count)")
        }
        return String(repeating: "Hello \(name)! ", count: count)
    }
    
    /// A void function that performs an action
    /// - Parameter message: Message to process
    @MCPTool
    func voidFunction(message: String) {
        // Just a test function
    }
    
    /// An async function that returns a result
    /// - Parameter delay: Time to wait in seconds
    /// - Returns: A completion message
    @MCPTool
    func asyncFunction(delay: Double) async -> String {
        return "Completed after \(delay) seconds"
    }
    
    /// A complex function that demonstrates all features
    /// - Parameters:
    ///   - input: The input string
    ///   - count: Number of times to process
    ///   - flag: Optional processing flag
    /// - Returns: The processed result
    /// - Throws: If processing fails
    @MCPTool
    func complexFunction(input: String, count: Int, flag: Bool = false) async throws -> String {
        if count < 0 {
            throw MCPToolError.invalidArgumentType(parameterName: "count", expectedType: "positive Int", actualValue: "\(count)")
        }
        return "Processed"
    }
}

@Test("OpenAPI spec correctly describes simple function")
func testSimpleFunctionSpec() {
    let server = TestAPIServer()
    let spec = OpenAPISpec(server: server, scheme: "http", host: "localhost:8080")
    
    // Get the path for simpleFunction
    let path = "/test_server/simpleFunction"
    guard let pathItem = spec.paths[path] else {
        #expect(Bool(false), "Path \(path) not found in spec")
        return
    }
    
    guard let operation = pathItem.post else {
        #expect(Bool(false), "POST operation not found for \(path)")
        return
    }
    
    // Check basic operation properties
    #expect(operation.summary == "simpleFunction")
    #expect(operation.description == "A simple function that returns a string")
    
    // Check response schema
    guard let response = operation.responses["200"] else {
        #expect(Bool(false), "200 response not found")
        return
    }
    
    #expect(response.description == "A greeting message")
    #expect(response.content?["application/json"] != nil)
}

@Test("OpenAPI spec correctly describes throwing function")
func testThrowingFunctionSpec() {
    let server = TestAPIServer()
    let spec = OpenAPISpec(server: server, scheme: "http", host: "localhost:8080")
    
    // Get the path for throwingFunction
    let path = "/test_server/throwingFunction"
    guard let pathItem = spec.paths[path] else {
        #expect(Bool(false), "Path \(path) not found in spec")
        return
    }
    
    guard let operation = pathItem.post else {
        #expect(Bool(false), "POST operation not found for \(path)")
        return
    }
    
    // Check parameters
    guard let requestBody = operation.requestBody else {
        #expect(Bool(false), "Request body not found")
        return
    }
    
    guard let content = requestBody.content["application/json"] else {
        #expect(Bool(false), "JSON content not found in request body")
        return
    }
	
	print(content)
    
    // Check responses
    #expect(operation.responses["200"] != nil, "200 response should exist")
    #expect(operation.responses["400"] != nil, "400 response should exist for throwing function")
    
    if let errorResponse = operation.responses["400"] {
        #expect(errorResponse.description == "The function threw an error")
        #expect(errorResponse.content?["application/json"] != nil)
    }
}

@Test("OpenAPI spec correctly describes void function")
func testVoidFunctionSpec() {
    let server = TestAPIServer()
    let spec = OpenAPISpec(server: server, scheme: "http", host: "localhost")
    
    // Check if the path exists
    #expect(spec.paths["/test_server/voidFunction"] != nil)
    
    // Get the operation
    let operation = spec.paths["/test_server/voidFunction"]?.post
    #expect(operation != nil)
    
    // Check parameters via request body
    guard let requestBody = operation?.requestBody,
          let content = requestBody.content["application/json"] else {
        #expect(Bool(false), "Request body or JSON content not found")
        return
    }
    
    // Check parameter schema
    if case let .object(properties: properties, required: _, description: _) = content.schema {
        #expect(properties["message"] != nil)
        if case let .string(description: description) = properties["message"] {
            #expect(description == "Message to process")
        } else {
            #expect(Bool(false), "Message parameter should be a string")
        }
    } else {
        #expect(Bool(false), "Request body should be an object")
    }
    
    // Check response
    let response = operation?.responses["200"]
    #expect(response != nil)
    print("Response description: \(response?.description ?? "nil")")
    #expect(response?.description == "A void function that performs an action")
    
    // Check response schema
    let schema = response?.content?["application/json"]?.schema
    #expect(schema != nil)
    if case let .string(description: description) = schema {
        #expect(description == "Empty string (void function)")
    } else {
        #expect(Bool(false), "Response schema should be a string")
    }
}

@Test("OpenAPI spec correctly describes complex function")
func testComplexFunctionSpec() {
    let server = TestAPIServer()
    let spec = OpenAPISpec(server: server, scheme: "http", host: "localhost:8080")
    
    // Get the path for complexFunction
    let path = "/test_server/complexFunction"
    guard let pathItem = spec.paths[path] else {
        #expect(Bool(false), "Path \(path) not found in spec")
        return
    }
    
    guard let operation = pathItem.post else {
        #expect(Bool(false), "POST operation not found for \(path)")
        return
    }
    
    // Check request body
    guard let requestBody = operation.requestBody,
          let _ = requestBody.content["application/json"] else {
        #expect(Bool(false), "Request body or JSON content not found")
        return
    }
    
    // Verify it has both success and error responses
    #expect(operation.responses["200"] != nil, "200 response should exist")
    #expect(operation.responses["400"] != nil, "400 response should exist for throwing function")
    
    // Check that the request body is required
    #expect(requestBody.required == true)
} 
