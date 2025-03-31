import Foundation
@testable import SwiftMCP

/// A generic mock client that can work with any MCPServer
class MockClient {
    private let server: MCPServer
    
    init(server: MCPServer) {
        self.server = server
    }
    
    func send(_ request: JSONRPCMessage) async throws -> JSONRPCMessage {
        guard let response = await server.handleRequest(request) else {
            throw MCPError.invalidResponse
        }
        return response
    }
} 