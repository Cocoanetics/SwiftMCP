import Foundation
import SwiftMCP

@MainActor
class Calculator {
    // Define functions with the MCPFunction macro
    @MCPFunction
    func add(a: Int, b: Int) -> Int {
        return a + b
    }
    
    @MCPFunction
    func subtract(a: Int, b: Int) -> Int {
        return a - b
    }
    
    @MCPFunction
    func multiply(a: Int, b: Int) -> Int {
        return a * b
    }
    
    @MCPFunction
    func divide(numerator: Double, denominator: Double) -> Double {
        return numerator / denominator
    }
    
    @MCPFunction
    func greet(name: String) {
        print("Hello, \(name)!")
    }
	
	@MCPFunction
	func ping() -> String {
		return "pong"
	}
    
    // Initialize the calculator class
    init() {
        // The functions are automatically registered by the macro
        // No manual registration needed
    }
    
    // Demonstrate the functions
    func demonstrateFunctions() {
        print("Function Demonstrations:")
        print("2 + 3 = \(add(a: 2, b: 3))")
        print("5 - 2 = \(subtract(a: 5, b: 2))")
        print("4 * 6 = \(multiply(a: 4, b: 6))")
        print("10 / 2 = \(divide(numerator: 10, denominator: 2))")
        greet(name: "Swift Developer!")
        
        print("\nFunction Metadata (JSON):")
        for function in MCPFunctionRegistry.shared.getAllFunctions() {
            print("\(function.name): \(function.toJSON())")
        }
        
        print("\nAll Functions JSON:")
        print(MCPFunctionRegistry.shared.getAllFunctionsJSON())
    }
} 
