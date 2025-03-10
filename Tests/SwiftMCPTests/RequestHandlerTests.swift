import XCTest
import SwiftMCP
import AnyCodable
@testable import SwiftMCPDemo

final class MCPServerTests: XCTestCase {
    var calculator: Calculator!
    
    override func setUp() {
        super.setUp()
        calculator = Calculator()
    }
    
    override func tearDown() {
        calculator = nil
        super.tearDown()
    }
    
    func testInitializeRequest() throws {
        // Create a request
        let request = SwiftMCP.JSONRPCRequest(
            jsonrpc: "2.0",
            id: 1,
            method: "initialize",
            params: [:]
        )
        
        // Handle the request
        let responseString = calculator.handleRequest(request)
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(JSONRPC.Response.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, .number(1))
    }
    
    func testToolsListRequest() throws {
        // Create a request
        let request = SwiftMCP.JSONRPCRequest(
            jsonrpc: "2.0",
            id: 2,
            method: "tools/list",
            params: [:]
        )
        
        // Handle the request
        let responseString = calculator.handleRequest(request)
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(SwiftMCP.ToolsResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 2)
        XCTAssertFalse(response.result.tools.isEmpty)
        
        // Check that the tools include the expected functions
        let toolNames = response.result.tools.map { $0.name }
        XCTAssertTrue(toolNames.contains("add"))
        XCTAssertTrue(toolNames.contains("testArray"))
    }
    
    func testToolCallRequest() throws {
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
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(SwiftMCP.ToolCallResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 3)
        XCTAssertEqual(response.result.status, "success")
        XCTAssertEqual(response.result.content.first?.text, "5")
    }
    
    func testToolCallRequestWithError() throws {
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
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(SwiftMCP.ToolCallResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 4)
        XCTAssertEqual(response.result.status, "error")
        XCTAssertTrue(response.result.content.first?.text.contains("Unknown tool") ?? false)
    }
    
    func testToolCallRequestWithInvalidArgument() throws {
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
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(SwiftMCP.ToolCallResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 5)
        XCTAssertEqual(response.result.status, "error")
        XCTAssertTrue(response.result.content.first?.text.contains("Parameter 'a' expected type 'Int'") ?? false)
    }
} 