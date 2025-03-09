import Foundation
import SwiftMCP

@MCPServer
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
	func testArray(a: [Int]) -> String {
		
		return a.map(String.init).joined(separator: ", ")
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
    
    /// Returns a greeting message with the provided name
    /// - Parameter name: Name of the person to greet
    /// - Returns: The greeting message
    @MCPFunction(description: "Shows a greeting message")
    func greet(name: String) -> String {
        return "Hello, \(name)!"
    }
	
    /** A simple ping function that returns 'pong' */
	@MCPFunction
	func ping() -> String {
		return "pong"
	}
}
