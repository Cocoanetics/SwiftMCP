import SwiftMCP

/**
 A Calculator for simple math operations like addition, subtraction, and more.
 */
@MCPServer(version: "1.0.0", name: "SwiftMCP Demo")
class Calculator {
/**
     Adds two numbers together and returns their sum.
     
     - Parameter a: First number to add
     - Parameter b: Second number to add
     - Returns: The sum of a and b
     */
    @MCPTool(description: "Performs addition of two numbers")
    func add(a: Double, b: Double) -> Double {
        return a + b
    }
} 