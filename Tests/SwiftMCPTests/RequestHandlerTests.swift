import XCTest
import SwiftMCP
import AnyCodable
@testable import SwiftMCPDemo

final class RequestHandlerTests: XCTestCase {
    var calculator: Calculator!
    var requestHandler: RequestHandler!
    
    override func setUp() {
        super.setUp()
        calculator = Calculator()
        requestHandler = RequestHandler(calculator: calculator)
    }
    
    override func tearDown() {
        calculator = nil
        requestHandler = nil
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
        let responseString = requestHandler.handleRequest(request)
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(InitializeResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 1)
        XCTAssertEqual(response.result.serverInfo.name, "mcp-calculator")
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
        let responseString = requestHandler.handleRequest(request)
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(ToolsListResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 2)
        XCTAssertFalse(response.result.tools.isEmpty)
        
        // Check that the tools include the expected functions
        let toolNames = response.result.tools.map { $0.name }
        XCTAssertTrue(toolNames.contains("add"))
        XCTAssertTrue(toolNames.contains("subtract"))
        XCTAssertTrue(toolNames.contains("multiply"))
        XCTAssertTrue(toolNames.contains("divide"))
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
        let responseString = requestHandler.handleRequest(request)
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(ToolCallResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 3)
        XCTAssertFalse(response.result.isError)
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
        let responseString = requestHandler.handleRequest(request)
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(ToolCallResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 4)
        XCTAssertTrue(response.result.isError)
        XCTAssertTrue(response.result.content.first?.text.contains("Unknown tool") ?? false)
    }
    
    func testToolCallRequestWithInvalidArgument() throws {
        // Create a request with an invalid argument type
        let request = SwiftMCP.JSONRPCRequest(
            jsonrpc: "2.0",
            id: 5,
            method: "tools/call",
            params: [
                "name": AnyCodable("divide"),
                "arguments": AnyCodable([
                    "numerator": "not_a_number"
                ])
            ]
        )
        
        // Handle the request
        let responseString = requestHandler.handleRequest(request)
        XCTAssertNotNil(responseString)
        
        // Decode the response
        guard let responseData = responseString?.data(using: String.Encoding.utf8) else {
            XCTFail("Failed to convert response to data")
            return
        }
        
        let response = try JSONDecoder().decode(ToolCallResponse.self, from: responseData)
        XCTAssertEqual(response.jsonrpc, "2.0")
        XCTAssertEqual(response.id, 5)
        XCTAssertTrue(response.result.isError)
        XCTAssertTrue(response.result.content.first?.text.contains("Parameter 'numerator' expected type 'Double'") ?? false)
    }
} 