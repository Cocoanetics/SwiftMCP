import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Test("Ping Request")
func testPingRequest() async throws {
    // Create a calculator instance
    let calculator = Calculator()
    
    // Create a ping request
    let pingRequest = JSONRPCMessage.request(
        id: 1,
        method: "ping"
    )
    
    // Handle the request
    guard let message = await calculator.handleMessage(pingRequest) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    
    #expect(response.id == .int(1))
} 
