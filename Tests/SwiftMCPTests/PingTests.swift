import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Test("Ping Request")
func testPingRequest() async throws {
    // Create a calculator instance
    let calculator = Calculator()
    
    // Create a ping request
    let pingRequest = JSONRPCMessage(
        jsonrpc: "2.0",
        id: 10,
        method: "ping",
        params: nil
    )
    
    // Handle the request
    let response = unwrap(await calculator.handleRequest(pingRequest))
    
    // Verify the response format
    #expect(response.jsonrpc == "2.0", "jsonrpc should be 2.0")
    #expect(response.id == 10, "id should match the request id")
    #expect(response.result != nil, "result should not be nil")
    #expect(response.params == nil, "params should be nil")
    
    // Verify that the result is an empty object
    guard let resultDict = response.result else {
        throw TestError("Failed to extract result from response")
    }
    
    #expect(resultDict.isEmpty, "Result should be an empty object")
} 
