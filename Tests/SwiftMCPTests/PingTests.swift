import Foundation
import Testing
import SwiftMCP
import AnyCodable

@Test("Ping Request")
func testPingRequest() async throws {
    // Create a calculator instance
    let calculator = Calculator()
    
    // Create a ping request
    let pingRequest = SwiftMCP.JSONRPCRequest(
        jsonrpc: "2.0",
        id: 10,
        method: "ping",
        params: nil
    )
    
    // Handle the request
    let response = unwrap(await calculator.handleRequest(pingRequest) as? JSONRPC.Response)
    
    // Verify the response format
    #expect(response.jsonrpc == "2.0", "jsonrpc should be 2.0")
    #expect(response.id == .number(10), "id should match the request id")
    
    // Verify that the result is an empty object
    guard let resultDict = response.result?.value as? [String: Any] else {
        throw TestError("Failed to extract result from response")
    }
    
    #expect(resultDict.isEmpty, "Result should be an empty object")
    
    // Test with a different ID
    let pingRequest2 = SwiftMCP.JSONRPCRequest(
        jsonrpc: "2.0",
        id: 123,
        method: "ping",
        params: nil
    )
    
    let response2 = unwrap(await calculator.handleRequest(pingRequest2) as? JSONRPC.Response)
    
    #expect(response2.jsonrpc == "2.0", "jsonrpc should be 2.0")
    #expect(response2.id == .number(123), "id should match the request id")
    
    guard let resultDict2 = response2.result?.value as? [String: Any] else {
        throw TestError("Failed to extract result from response")
    }
    
    #expect(resultDict2.isEmpty, "Result should be an empty object")
} 
