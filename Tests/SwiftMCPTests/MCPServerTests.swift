import Foundation
import Testing
import SwiftMCP
import AnyCodable
@testable import SwiftMCPDemo

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
    let responseString = calculator.handleRequest(request)
    #expect(responseString != nil)
    
    // Decode the response
    guard let responseString = responseString,
          let responseData = responseString.data(using: String.Encoding.utf8) else {
        throw TestError("Failed to convert response to data")
    }
    
    let response = try JSONDecoder().decode(JSONRPC.Response.self, from: responseData)
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
    let responseString = calculator.handleRequest(request)
    #expect(responseString != nil)
    
    // Decode the response
    guard let responseString = responseString,
          let responseData = responseString.data(using: String.Encoding.utf8) else {
        throw TestError("Failed to convert response to data")
    }
    
    let response = try JSONDecoder().decode(SwiftMCP.ToolsResponse.self, from: responseData)
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
    let responseString = calculator.handleRequest(request)
    #expect(responseString != nil)
    
    // Decode the response
    guard let responseString = responseString,
          let responseData = responseString.data(using: String.Encoding.utf8) else {
        throw TestError("Failed to convert response to data")
    }
    
    let response = try JSONDecoder().decode(SwiftMCP.ToolCallResponse.self, from: responseData)
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
    let responseString = calculator.handleRequest(request)
    #expect(responseString != nil)
    
    // Decode the response
    guard let responseString = responseString,
          let responseData = responseString.data(using: String.Encoding.utf8) else {
        throw TestError("Failed to convert response to data")
    }
    
    let response = try JSONDecoder().decode(SwiftMCP.ToolCallResponse.self, from: responseData)
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
    let responseString = calculator.handleRequest(request)
    #expect(responseString != nil)
    
    // Decode the response
    guard let responseString = responseString,
          let responseData = responseString.data(using: String.Encoding.utf8) else {
        throw TestError("Failed to convert response to data")
    }
    
    let response = try JSONDecoder().decode(SwiftMCP.ToolCallResponse.self, from: responseData)
    #expect(response.jsonrpc == "2.0")
    #expect(response.id == 5)
    #expect(response.result.status == "error")
    #expect(response.result.content.first?.text.contains("Parameter 'a' expected type 'Int'") ?? false)
}
