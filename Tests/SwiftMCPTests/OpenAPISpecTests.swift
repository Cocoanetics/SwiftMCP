import Testing
import Foundation
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
            throw MCPToolError.invalidArgumentType(parameterName: "count", expectedType: "positive Int", actualType: "foo")
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
            throw MCPToolError.invalidArgumentType(parameterName: "count", expectedType: "positive Int", actualType: "foo")
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
    
    // Verify request body schema
    if case .object(let object, _) = content.schema {
		#expect(object.description == "A function that takes parameters and can throw")
		#expect(object.required.contains("name"))
		#expect(object.required.contains("count"))
        
        // Check name parameter
        guard case let .string(title: _, description: nameDesc, format: _, minLength: _, maxLength: _, defaultValue: _) = object.properties["name"] else {
            #expect(Bool(false), "name parameter should be a string")
            return
        }
        #expect(nameDesc == "The name to greet")
        
        // Check count parameter
        guard case let .number(title: _, description: countDesc, minimum: _, maximum: _, defaultValue: _) = object.properties["count"] else {
            #expect(Bool(false), "count parameter should be a number")
            return
        }
        #expect(countDesc == "Number of times to repeat")
    } else {
        #expect(Bool(false), "Request body should be an object")
    }
    
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
    if case .object(let object, _) = content.schema {
		#expect(object.properties["message"] != nil)
        if case let .string(title: _, description: description, format: _, minLength: _, maxLength: _, defaultValue: _) = object.properties["message"] {
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
    #expect(response?.description == "A void function that performs an action")
    
    // Check response schema
    let schema = response?.content?["application/json"]?.schema
    #expect(schema != nil)
    if case let .string(title: _, description: description, format: _, minLength: _, maxLength: _, defaultValue: _) = schema {
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

// Test model for SchemaRepresentable
@Schema
struct TestWeatherForecast: Codable {
    let temperature: Double
    let condition: String
    let timestamp: Date
}

// Test enum for CaseIterable
enum TestWeatherCondition: String, CaseIterable, Codable {
    case sunny, cloudy, rainy, snowy
}

// Test server with various return types
@MCPServer(name: "TestServer", version: "1.0")
class TestServer {
    
    /// Get a single weather forecast
    /// - Returns: A weather forecast with temperature, condition and timestamp
    @MCPTool
    func getSingleForecast() -> TestWeatherForecast {
        fatalError("Not implemented")
    }
    
    /// Get multiple weather forecasts
    /// - Returns: An array of weather forecasts
    @MCPTool
    func getMultipleForecasts() -> [TestWeatherForecast] {
        fatalError("Not implemented")
    }
    
    /// Get a single weather condition
    /// - Returns: A weather condition (sunny, cloudy, rainy, or snowy)
    @MCPTool
    func getSingleCondition() -> TestWeatherCondition {
        fatalError("Not implemented")
    }
    
    /// Get multiple weather conditions
    /// - Returns: An array of weather conditions
    @MCPTool
    func getMultipleConditions() -> [TestWeatherCondition] {
        fatalError("Not implemented")
    }
    
    /// Get an array of strings
    /// - Returns: A basic array of strings
    @MCPTool
    func getBasicArray() -> [String] {
        fatalError("Not implemented")
    }
}

@Test("OpenAPI spec correctly handles various return types")
func testOpenAPISpecGeneration() throws {
    let server = TestServer()
    let spec = OpenAPISpec(server: server, scheme: "http", host: "localhost:8080")
    
    // Test paths exist
    #expect(spec.paths["/testserver/getSingleForecast"] != nil, "Missing path for getSingleForecast")
    #expect(spec.paths["/testserver/getMultipleForecasts"] != nil, "Missing path for getMultipleForecasts")
    #expect(spec.paths["/testserver/getSingleCondition"] != nil, "Missing path for getSingleCondition")
    #expect(spec.paths["/testserver/getMultipleConditions"] != nil, "Missing path for getMultipleConditions")
    #expect(spec.paths["/testserver/getBasicArray"] != nil, "Missing path for getBasicArray")
    
    // Test single SchemaRepresentable response
    guard let singleForecastOp = spec.paths["/testserver/getSingleForecast"]?.post,
          let singleForecastSchema = singleForecastOp.responses["200"]?.content?["application/json"]?.schema else {
        #expect(Bool(false), "Failed to get schema for getSingleForecast")
        return
    }
    #expect(singleForecastSchema.type == "object", "Expected object schema for single forecast")
    
    // Test array of SchemaRepresentable response
    guard let multipleForecastsOp = spec.paths["/testserver/getMultipleForecasts"]?.post,
          let multipleForecastsSchema = multipleForecastsOp.responses["200"]?.content?["application/json"]?.schema else {
        #expect(Bool(false), "Failed to get schema for getMultipleForecasts")
        return
    }
    #expect(multipleForecastsSchema.type == "array", "Expected array schema for multiple forecasts")
    if case .array(let items, title: _, description: _, defaultValue: _) = multipleForecastsSchema {
        #expect(items.type == "object", "Expected object schema for array items")
    } else {
        #expect(Bool(false), "Expected array schema")
    }
    
    // Test single CaseIterable response
    guard let singleConditionOp = spec.paths["/testserver/getSingleCondition"]?.post,
          let singleConditionSchema = singleConditionOp.responses["200"]?.content?["application/json"]?.schema else {
        #expect(Bool(false), "Failed to get schema for getSingleCondition")
        return
    }
	
    #expect(singleConditionSchema.type == "string", "Expected string schema for single condition")
    if case .enum(let enumValues, title: _, description: _, enumNames: _, defaultValue: _) = singleConditionSchema {
        #expect(enumValues == ["sunny", "cloudy", "rainy", "snowy"],
               "Enum values don't match expected values")
    } else {
        #expect(Bool(false), "Expected string schema with enum values")
    }
    
    // Test array of CaseIterable response
    guard let multipleConditionsOp = spec.paths["/testserver/getMultipleConditions"]?.post,
          let multipleConditionsSchema = multipleConditionsOp.responses["200"]?.content?["application/json"]?.schema else {
        #expect(Bool(false), "Failed to get schema for getMultipleConditions")
        return
    }
    #expect(multipleConditionsSchema.type == "array", "Expected array schema for multiple conditions")
    if case .array(let items, title: _, description: _, defaultValue: _) = multipleConditionsSchema {
        #expect(items.type == "string", "Expected string schema for array items")
        if case .enum(let enumValues, title: _, description: _, enumNames: _, defaultValue: _) = items {
            #expect(Set(enumValues) == Set(["sunny", "cloudy", "rainy", "snowy"]), 
                   "Array items enum values don't match expected values")
        } else {
            #expect(Bool(false), "Expected string schema with enum values for array items")
        }
    } else {
        #expect(Bool(false), "Expected array schema")
    }
    
    // Test basic array response
    guard let basicArrayOp = spec.paths["/testserver/getBasicArray"]?.post,
          let basicArraySchema = basicArrayOp.responses["200"]?.content?["application/json"]?.schema else {
        #expect(Bool(false), "Failed to get schema for getBasicArray")
        return
    }
	
    #expect(basicArraySchema.type == "array", "Expected array schema for basic array")
    if case .array(let items, title: _, description: _, defaultValue: _) = basicArraySchema {
        #expect(items.type == "string", "Expected string schema for array items")
    } else {
        #expect(Bool(false), "Expected array schema")
    }
}

private extension JSONSchema {
    var type: String {
        switch self {
        case .string: return "string"
        case .number: return "number"
        case .boolean: return "boolean"
        case .array: return "array"
        case .object: return "object"
        case .enum: return "string"
        case .oneOf: return "oneOf"
        }
    }
} 
