import Testing
import SwiftMCP

// Test class that uses the MCPServer macro without explicitly conforming to MCPServer
@MCPServer
class AutoConformingCalculator {
    /// Adds two integers and returns their sum
    /// - Parameter a: First number to add
    /// - Parameter b: Second number to add
    /// - Returns: The sum of a and b
    @MCPTool
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
}

@Test("Auto Protocol Conformance")
func testAutoProtocolConformance() async {
    // Create an instance of the class
    let calculator = AutoConformingCalculator()
    
    // Verify that it conforms to MCPServer by checking if mcpTools is available
    #expect(!calculator.mcpToolMetadata.isEmpty)
    
    // Verify that we can call a tool through the MCPServer protocol method
    do {
        let result = try await calculator.callTool("add", arguments: ["a": 2, "b": 3])
        #expect(result as? Int == 5)
    } catch {
        #expect(Bool(false), "Should not throw an error: \(error)")
    }
} 
