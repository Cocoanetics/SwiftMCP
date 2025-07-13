import Foundation
@testable import SwiftMCP

/// A generic mock client that can work with any MCPServer
/// Simulates JSON serialization/deserialization like a real JSON-RPC client
class MockClient {
    private let server: MCPServer
    
    init(server: MCPServer) {
        self.server = server
    }
    
    func send(_ request: JSONRPCMessage) async -> JSONRPCMessage? {
        // Get response from server
        let response = await server.handleMessage(request)
        
        // Simulate JSON round-trip to match real-world behavior
        guard let response = response else { return nil }
        
        do {
            // Encode to JSON like it would go over the wire
            let encoder = JSONEncoder()
            let jsonData = try encoder.encode(response)
            
            // Decode back like a client would receive it
            let decoder = JSONDecoder()
            let roundTripResponse = try decoder.decode(JSONRPCMessage.self, from: jsonData)
            
            return roundTripResponse
        } catch {
            // MockClient JSON round-trip failed: \(error)
            return response // Fallback to original if round-trip fails
        }
    }
} 
