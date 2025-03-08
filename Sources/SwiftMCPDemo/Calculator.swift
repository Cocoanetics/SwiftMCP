import Foundation
import SwiftMCP

@MCPTool
class Calculator {
    // Define functions with the MCPFunction macro
    @MCPFunction(description: "Adds two integers and returns their sum")
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
    
    @MCPFunction(description: "Subtracts the second integer from the first and returns the difference")
    func subtract(a: Int, b: Int) -> Int {
        return a - b
    }
    
    @MCPFunction(description: "Multiplies two integers and returns their product")
    func multiply(a: Int, b: Int) -> Int {
        return a * b
    }
    
    @MCPFunction(description: "Divides the numerator by the denominator and returns the quotient")
    func divide(numerator: Double, denominator: Double) -> Double {
        return numerator / denominator
    }
    
    @MCPFunction(description: "Prints a greeting message with the provided name")
    func greet(name: String) {
        print("Hello, \(name)!")
    }
	
	@MCPFunction(description: "A simple ping function that returns 'pong'")
	func ping() -> String {
		return "pong"
	}
    
    // Initialize the calculator class
    init() {
        // No manual registration needed - metadata is generated by the macro
    }
    
    // Demonstrate the functions
    func demonstrateFunctions() {
        print("Function Demonstrations:")
        print("2 + 3 = \(add(a: 2, b: 3))")
        print("5 - 2 = \(subtract(a: 5, b: 2))")
        print("4 * 6 = \(multiply(a: 4, b: 6))")
        print("10 / 2 = \(divide(numerator: 10, denominator: 2))")
        greet(name: "Swift Developer!")
    }
} 
