import Testing
import SwiftMCP
import Foundation
import AnyCodable

// Utility function to unwrap optionals in tests
func unwrap<T>(_ optional: T?, message: Comment = "Unexpected nil") -> T {
    #expect(optional != nil, message)
    return optional!
}



@MCPServer(name: "CustomCalculator", version: "2.0")
final class CustomNameCalculator: MCPServer {
    @MCPTool(description: "Simple addition")
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
}

@MCPServer
final class DefaultNameCalculator: MCPServer {
    @MCPTool(description: "Simple addition")
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
}
