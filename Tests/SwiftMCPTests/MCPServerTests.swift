import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Test
func testInitializeRequest() async throws {
    let calculator = Calculator()
    
    // Create a request
    let request = JSONRPCMessage(
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: [:]
    )
    
    // Handle the request
    let response = unwrap(await calculator.handleRequest(request))
    
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 1)
    #expect(response.result != nil)
    #expect(response.params == nil)
    
    // Check result contents
    guard let result = response.result else {
        throw TestError("Result is missing")
    }
    
    #expect(result["protocolVersion"]?.value as? String == "2024-11-05")
    
    guard let capabilities = result["capabilities"]?.value as? [String: Any] else {
        throw TestError("Capabilities not found or not a dictionary")
    }
    
    #expect(capabilities["experimental"] as? [String: String] == [:])
    
    guard let resources = capabilities["resources"] as? [String: Bool] else {
        throw TestError("Resources not found or not a dictionary")
    }
    #expect(resources["listChanged"] == false)
    
    guard let tools = capabilities["tools"] as? [String: Bool] else {
        throw TestError("Tools not found or not a dictionary")
    }
    #expect(tools["listChanged"] == false)
    
    guard let serverInfo = result["serverInfo"]?.value as? [String: String] else {
        throw TestError("ServerInfo not found or not a dictionary")
    }
    #expect(serverInfo["name"] != nil)
    #expect(serverInfo["version"] != nil)
}

@Test
func testToolsListRequest() async throws {
    let calculator = Calculator()
    
    // Create a request
    let request = JSONRPCMessage(
        jsonrpc: "2.0",
        id: 2,
        method: "tools/list",
        params: [:]
    )
    
    // Handle the request
    let response = unwrap(await calculator.handleRequest(request))
    
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 2)
    #expect(response.result != nil)
    #expect(response.params == nil)
    
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
    let request = JSONRPCMessage(
        jsonrpc: "2.0",
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
    let response = unwrap(await calculator.handleRequest(request))
    
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 3)
    #expect(response.result != nil)
    #expect(response.params == nil)
    
    guard let result = response.result else {
        throw TestError("Result is missing")
    }
    
    guard let content = result["content"]?.value as? [[String: String]] else {
        throw TestError("Content not found or not an array")
    }
    
    #expect(!content.isEmpty)
    #expect(content[0]["type"] == "text")
    #expect(content[0]["text"] == "5")
}

@Test
func testToolCallRequestWithError() async throws {
    let calculator = Calculator()
    
    // Create a request with an unknown tool
    let request = JSONRPCMessage(
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: [
            "name": AnyCodable("unknown_tool"),
            "arguments": AnyCodable([:])
        ]
    )
    
    // Handle the request
    let response = unwrap(await calculator.handleRequest(request))
    
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 4)
    #expect(response.error != nil)
    #expect(response.result == nil)
    #expect(response.params == nil)
    
    guard let error = response.error else {
        throw TestError("Error is missing")
    }
    
    #expect(error.code == -32000)
    #expect(error.message.contains("not found on the server"))
}

@Test
func testToolCallRequestWithInvalidArgument() async throws {
    let calculator = Calculator()
    
    // Create a request with an invalid argument type
    let request = JSONRPCMessage(
        jsonrpc: "2.0",
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
    let response = unwrap(await calculator.handleRequest(request))
    
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 5)
    #expect(response.error != nil)
    #expect(response.result == nil)
    #expect(response.params == nil)
    
    guard let error = response.error else {
        throw TestError("Error is missing")
    }
    
    #expect(error.code == -32000)
    #expect(error.message.contains("expected type Int"))
}

@Test("Custom Name and Version")
func testCustomNameAndVersion() async throws {
    // Create an instance of CustomNameCalculator
    let calculator = CustomNameCalculator()
    
    // Get the response using our test method
    let response = calculator.createInitializeResponse(id: 1)
    
    // Extract server info from the response using dictionary access
    guard let result = response.result,
          let serverInfo = result["serverInfo"]?.value as? [String: String],
          let name = serverInfo["name"],
          let version = serverInfo["version"] else {
        throw TestError("Failed to extract server info from response")
    }
    
    #expect(name == "CustomCalculator", "Server name should match specified name")
    #expect(version == "2.0", "Server version should match specified version")
}

@Test("Default Name and Version")
func testDefaultNameAndVersion() async throws {
    // Create an instance of DefaultNameCalculator
    let calculator = DefaultNameCalculator()
    
    // Get the response using our test method
    let response = calculator.createInitializeResponse(id: 1)
    
    // Extract server info from the response using dictionary access
    guard let result = response.result,
          let serverInfo = result["serverInfo"]?.value as? [String: String],
          let name = serverInfo["name"],
          let version = serverInfo["version"] else {
        throw TestError("Failed to extract server info from response")
    }
    
    #expect(name == "DefaultNameCalculator", "Server name should match class name")
    #expect(version == "1.0", "Server version should be default value")
}
