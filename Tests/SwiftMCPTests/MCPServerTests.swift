import Foundation
import Testing
import SwiftMCP
import AnyCodable

@Test
func testInitializeRequest() throws {
    let calculator = Calculator()
    
    // Create a request
    let request = SwiftMCP.JSONRPCRequest(
        jsonrpc: "2.0",
        id: 1,
        method: "initialize",
        params: [:]
    )
    
    // Handle the request
	let response = unwrap(calculator.handleRequest(request) as? JSONRPC.Response)
    
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == .number(1))
}

@Test
func testToolsListRequest() throws {
    let calculator = Calculator()
    
    // Create a request
    let request = SwiftMCP.JSONRPCRequest(
        jsonrpc: "2.0",
        id: 2,
        method: "tools/list",
        params: [:]
    )
    
	// Handle the request
	let response = unwrap(calculator.handleRequest(request) as? ToolsResponse)
	
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 2)
    #expect(!response.result.tools.isEmpty)
    
    // Check that the tools include the expected functions
    let toolNames = response.result.tools.map { $0.name }
    #expect(toolNames.contains("add"))
    #expect(toolNames.contains("testArray"))
}

@Test
func testToolCallRequest() throws {
    let calculator = Calculator()
    
    // Create a request
    let request = SwiftMCP.JSONRPCRequest(
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
	let response = unwrap(calculator.handleRequest(request) as? ToolCallResponse)
    
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 3)
    #expect(response.result.status == "success")
    #expect(response.result.content.first?.text == "5")
}

@Test
func testToolCallRequestWithError() throws {
    let calculator = Calculator()
    
    // Create a request with an unknown tool
    let request = SwiftMCP.JSONRPCRequest(
        jsonrpc: "2.0",
        id: 4,
        method: "tools/call",
        params: [
            "name": AnyCodable("unknown_tool"),
            "arguments": AnyCodable([:])
        ]
    )
    
	// Handle the request
	let response = unwrap(calculator.handleRequest(request) as? ToolCallResponse)

	#expect(response.jsonrpc == "2.0")
    #expect(response.id == 4)
    #expect(response.result.status == "error")
    #expect(response.result.content.first?.text.contains("Unknown tool") ?? false)
}

@Test
func testToolCallRequestWithInvalidArgument() throws {
    let calculator = Calculator()
    
    // Create a request with an invalid argument type
    let request = SwiftMCP.JSONRPCRequest(
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
	let response = unwrap(calculator.handleRequest(request) as? ToolCallResponse)
	
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 5)
    #expect(response.result.status == "error")
    #expect(response.result.content.first?.text.contains("Parameter 'a' expected type 'Int'") ?? false)
}

@Test("Custom Name and Version")
func testCustomNameAndVersion() throws {
    // Create an instance of CustomNameCalculator
    let calculator = CustomNameCalculator()
    
    // Get the response using our test method
    let response = calculator.createInitializeResponse(id: 1)
    
    // Extract server info from the response using dictionary access
    guard let resultDict = response.result?.value as? [String: Any],
          let serverInfoDict = resultDict["serverInfo"] as? [String: Any],
          let name = serverInfoDict["name"] as? String,
          let version = serverInfoDict["version"] as? String else {
        throw TestError("Failed to extract server info from response")
    }
    
    #expect(name == "CustomCalculator", "Server name should match specified name")
    #expect(version == "2.0", "Server version should match specified version")
}

@Test("Default Name and Version")
func testDefaultNameAndVersion() throws {
    // Create an instance of DefaultNameCalculator
    let calculator = DefaultNameCalculator()
    
    // Get the response using our test method
    let response = calculator.createInitializeResponse(id: 1)
    
    // Extract server info from the response using dictionary access
    guard let resultDict = response.result?.value as? [String: Any],
          let serverInfoDict = resultDict["serverInfo"] as? [String: Any],
          let name = serverInfoDict["name"] as? String,
          let version = serverInfoDict["version"] as? String else {
        throw TestError("Failed to extract server info from response")
    }
    
    #expect(name == "DefaultNameCalculator", "Server name should match class name")
    #expect(version == "1.0", "Server version should be default value")
}
