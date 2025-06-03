import SwiftMCP

@MCPServer(version: "1.0.0")
struct Calculator {
    @MCPTool(description: "Adds two numbers together")
    func add(a: Double, b: Double) -> Double {
        return a + b
    }

    @MCPTool(description: "Greets a person by name")
    func greet(name: String) throws -> String {
        guard name.count >= 2 else {
            throw GreetingError.nameTooShort
        }
        return "Hello, \(name)!"
    }

    @MCPTool(description: "Sends a delayed greeting")
    func delayedGreet(name: String) async throws -> String {
        try await Task.sleep(for: .seconds(1))
        return try greet(name: name)
    }
} 