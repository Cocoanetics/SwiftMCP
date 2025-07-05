import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Test
func testInitializeRequest() async throws {
    let calculator = Calculator()
    
    // Create a request
    let request = JSONRPCMessage.request(
        id: 1,
        method: "initialize",
        params: [
            "protocolVersion": AnyCodable("2024-11-05"),
            "capabilities": AnyCodable([
                "experimental": [:],
                "resources": ["listChanged": false],
                "tools": ["listChanged": false]
            ] as [String: Any]),
            "clientInfo": AnyCodable([
                "name": "TestClient",
                "version": "1.0"
            ] as [String: Any])
        ]
    )
    
    // Handle the request
    guard let message = await calculator.handleMessage(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == .int(1))
    #expect(response.result != nil)

    // Check result contents
    guard let result = response.result else {
        throw TestError("Result is missing")
    }

    // Extract protocolVersion from the dictionary
    guard let protocolVersion = result["protocolVersion"]?.value as? String else {
        throw TestError("protocolVersion not found")
    }
    #expect(protocolVersion == "2024-11-05")

    // Extract the server capabilities
    guard let capabilitiesDict = result["capabilities"]?.value as? [String: Any] else {
        throw TestError("capabilities not found")
    }

    // Verify the capabilities - check if experimental is empty or doesn't exist
    let experimental = capabilitiesDict["experimental"] as? [String: Any] ?? [:]
    #expect(experimental.isEmpty, "Experimental should be empty")

    // Check tools capabilities
    guard let toolsDict = capabilitiesDict["tools"] as? [String: Any] else {
        throw TestError("Tools capabilities not found")
    }
    guard let listChanged = toolsDict["listChanged"] as? Bool else {
        throw TestError("listChanged not found in tools capabilities")
    }
    #expect(listChanged == false, "Tools listChanged should be false")

    // Ensure completion capability is advertised
    #expect(capabilitiesDict["completions"] != nil)

    // Check server info
    guard let serverInfoDict = result["serverInfo"]?.value as? [String: Any] else {
        throw TestError("serverInfo not found")
    }
    guard let name = serverInfoDict["name"] as? String else {
        throw TestError("server name not found")
    }
    guard let version = serverInfoDict["version"] as? String else {
        throw TestError("server version not found")
    }
    #expect(!name.isEmpty)
    #expect(!version.isEmpty)
}

@Test
func testToolsListRequest() async throws {
    let calculator = Calculator()
    
    // Create a request
    let request = JSONRPCMessage.request(
        id: 2,
        method: "tools/list",
        params: [:]
    )
    
    // Handle the request
    guard let message = await calculator.handleMessage(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == .int(2))
    #expect(response.result != nil)
    
    guard let result = response.result else {
        throw TestError("Result is missing")
    }
    
    guard let tools = result["tools"]?.value as? [MCPTool] else {
        throw TestError("Tools not found or not an array")
    }
    
    #expect(!tools.isEmpty)
    
    // Check that the tools include the expected functions
    let toolNames = tools.map { $0.name }
    #expect(toolNames.contains("add"))
    #expect(toolNames.contains("testArray"))
}

@Test
func testToolCallRequest() async throws {
    let calculator = Calculator()
    
    // Create a request
    let request = JSONRPCMessage.request(
        id: 3,
        method: "tools/call",
        params: [
            "name": AnyCodable("add"),
            "arguments": AnyCodable([
                "a": 2,
                "b": 3
            ])
        ]
    )
    
    // Handle the request
    guard let message = await calculator.handleMessage(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == .int(3))
    #expect(response.result != nil)
    
    guard let result = response.result else {
        throw TestError("Result is missing")
    }
    
    guard let content = result["content"]?.value as? [[String: String]] else {
        throw TestError("Content not found or not an array")
    }
    
    #expect(content.count == 1)
    #expect(content[0]["type"] == "text")
    #expect(content[0]["text"] == "5")
}

@Test
func testToolCallRequestWithError() async throws {
    let calculator = Calculator()
    
    // Create a request with an unknown tool
    let request = JSONRPCMessage.request(
        id: 4,
        method: "tools/call",
        params: [
            "name": AnyCodable("unknown_tool"),
            "arguments": AnyCodable([:])
        ]
    )
    
    // Handle the request
    guard let message = await calculator.handleMessage(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == .int(4))
    #expect(response.result != nil)
    
    guard let result = response.result else {
        throw TestError("Result is missing")
    }
    
    guard let content = result["content"]?.value as? [[String: String]] else {
        throw TestError("Content not found or not an array")
    }
    
    #expect(content.count == 1)
    #expect(content[0]["type"] == "text")
    guard let text = content[0]["text"] else {
        throw TestError("Text field missing in content")
    }
    #expect(text.contains("not found on the server"))
    
    guard let isError = result["isError"]?.value as? Bool else {
        throw TestError("isError flag not found")
    }
    #expect(isError)
}

@Test
func testToolCallRequestWithInvalidArgument() async throws {
    let calculator = Calculator()
    
    // Create a request with an invalid argument type
    let request = JSONRPCMessage.request(
        id: 5,
        method: "tools/call",
        params: [
            "name": AnyCodable("add"),
            "arguments": AnyCodable([
                "a": "not_a_number",
                "b": 3
            ])
        ]
    )
    
    // Handle the request
    guard let message = await calculator.handleMessage(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == .int(5))
    #expect(response.result != nil)
    
    guard let result = response.result else {
        throw TestError("Result is missing")
    }
    
    guard let content = result["content"]?.value as? [[String: String]] else {
        throw TestError("Content not found or not an array")
    }
    
    #expect(content.count == 1)
    #expect(content[0]["type"] == "text")
    guard let text = content[0]["text"] else {
        throw TestError("Text field missing in content")
    }
    #expect(text.contains("expected type Int"))
    
    guard let isError = result["isError"]?.value as? Bool else {
        throw TestError("isError flag not found")
    }
    #expect(isError)
}

@Test("Custom Name and Version")
func testCustomNameAndVersion() async throws {
    // Create an instance of CustomNameCalculator
    let calculator = CustomNameCalculator()
    
    // Get the response using our test method
    let response = calculator.createInitializeResponse(id: .int(1))

    // Extract server info from the response using pattern matching
    guard case .response(let responseData) = response else {
        throw TestError("Expected response case")
    }
    
    guard let result = responseData.result else {
        throw TestError("Failed to extract result from response")
    }
    
    guard let serverInfoDict = result["serverInfo"]?.value as? [String: Any] else {
        throw TestError("serverInfo not found")
    }
    guard let name = serverInfoDict["name"] as? String else {
        throw TestError("server name not found")
    }
    guard let version = serverInfoDict["version"] as? String else {
        throw TestError("server version not found")
    }
    
    #expect(name == "CustomCalculator")
    #expect(version == "2.0")
}

@Test("Default Name and Version")
func testDefaultNameAndVersion() async throws {
    // Create an instance that uses defaults
    let calculator = DefaultNameCalculator()
    
    // Get the response using our test method
    let response = calculator.createInitializeResponse(id: .int(1))

    // Extract server info from the response using pattern matching
    guard case .response(let responseData) = response else {
        throw TestError("Expected response case")
    }
    
    guard let result = responseData.result else {
        throw TestError("Failed to extract result from response")
    }
    
    guard let serverInfoDict = result["serverInfo"]?.value as? [String: Any] else {
        throw TestError("serverInfo not found")
    }
    guard let name = serverInfoDict["name"] as? String else {
        throw TestError("server name not found")
    }
    guard let version = serverInfoDict["version"] as? String else {
        throw TestError("server version not found")
    }
    
    #expect(name == "DefaultNameCalculator")
    #expect(version == "1.0")
}

@Test
func testUnknownMethodReturnsMethodNotFoundError() async throws {
    let calculator = Calculator()
    
    // Create a request with an unknown method
    let request = JSONRPCMessage.request(
        id: 99,
        method: "unknown_method",
        params: [:]
    )
    
    // Handle the request
    guard let message = await calculator.handleMessage(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .errorResponse(let response) = message else {
        #expect(Bool(false), "Expected errorResponse case")
        return
    }
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == .int(99))
    #expect(response.error.code == -32601)
    #expect(response.error.message == "Method not found")
}
