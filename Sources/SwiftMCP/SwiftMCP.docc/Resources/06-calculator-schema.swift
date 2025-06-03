import SwiftMCP

/**
 A Calculator for simple math operations like addition, subtraction, and more.
 */
@MCPServer(version: "1.0.0", name: "SwiftMCP Demo")
class Calculator {
/**
     Adds two numbers together and returns their sum.
     
     This documentation comment will be used to generate the OpenAPI schema
     for this tool, including the parameter descriptions and return value.
     
     - Parameter a: First number to add
     - Parameter b: Second number to add
     - Returns: The sum of a and b
     */
    @MCPTool(description: "Sends a delayed greeting")
    func add(a: Double, b: Double) -> Double {
        return a + b
    }
} 