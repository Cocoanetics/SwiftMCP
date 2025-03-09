import Foundation
import SwiftMCP

@MCPTool
class Calculator {
    /// Adds two integers and returns their sum
    /// - Parameter a: First number to add
    /// - Parameter b: Second number to add
    /// - Returns: The sum of a and b
    @MCPFunction(description: "Custom description: Performs addition of two numbers")
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
    
    /// Subtracts the second integer from the first and returns the difference
    /// - Parameter a: Number to subtract from
    /// - Parameter b: Number to subtract
    /// - Returns: The difference between a and b
    @MCPFunction
    func subtract(a: Int, b: Int = 3) -> Int {
        return a - b
    }
	
    /** 
     A test function that processes an array of integers
     - Parameter a: Array of integers to process
     */
	@MCPFunction(description: "Custom description: Tests array processing")
	func testArray(a: [Int]) {
		
	}
    
    /**
     Multiplies two integers and returns their product
     - Parameter a: First factor
     - Parameter b: Second factor
     - Returns: The product of a and b
     */
    @MCPFunction
    func multiply(a: Int, b: Int) -> Int {
        return a * b
    }
    
    /// Divides the numerator by the denominator and returns the quotient
    /// - Parameter numerator: Number to be divided
    /// - Parameter denominator: Number to divide by (defaults to 1.0)
    /// - Returns: The quotient of numerator divided by denominator
    @MCPFunction
    func divide(numerator: Double, denominator: Double = 1.0) -> Double {
        return numerator / denominator
    }
    
    /// Prints a greeting message with the provided name
    /// - Parameter name: Name of the person to greet
    @MCPFunction(description: "Shows a greeting message")
    func greet(name: String) {
        print("Hello, \(name)!")
    }
	
    /** A simple ping function that returns 'pong' */
	@MCPFunction
	func ping() -> String {
		return "pong"
	}
    
    // Initialize the calculator class
    init() {
        // No manual registration needed - metadata is generated by the macro
    }
    
    // Demonstrate the functions
    func demonstrateFunctions() {
//        print("Function Demonstrations:")
//        print("2 + 3 = \(add(a: 2, b: 3))")
//        print("5 - 2 = \(subtract(a: 5, b: 2))")
//        print("4 * 6 = \(multiply(a: 4, b: 6))")
//        print("10 / 2 = \(divide(numerator: 10, denominator: 2))")
//        print("10 / default = \(divide(numerator: 10))")
//        greet(name: "Swift Developer!")
//        greet() // Uses default value
//        print("2^3 = \(power(base: 2, exponent: 3))")
//        print("3^2 (default exponent) = \(power(base: 3))")
//        print("Formatted number: \(formatNumber(value: 1234.5678))")
//        print("Formatted number with custom precision: \(formatNumber(value: 1234.5678, precision: 3))")
//        print("Formatted number without separators: \(formatNumber(value: 1234.5678, includeThousandsSeparator: false))")
//        
//        // Print the JSON schema for all functions
//        print("\nJSON Schema for all functions:")
//        print(mcpTools.map { $0.inputSchema }.description)
    }
} 
