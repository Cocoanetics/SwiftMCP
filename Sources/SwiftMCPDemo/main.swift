// SwiftMCP - Function Metadata Generator Demo
// A demonstration of using macros to generate JSON descriptions of functions

import Foundation
import SwiftMCP

// Main async function
@MainActor
func run() async throws {
    print("SwiftMCP - Function Metadata Generator")
    print("--------------------------------------")
    
    // Create an instance of Calculator
    let calculator = Calculator()
    
    // Demonstrate the functions
    calculator.demonstrateFunctions()
	
	print(calculator.mcpTools)
	
	// Use the standard JSON encoder for the array output
	let encoder = JSONEncoder()
	encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
	
	let jsonData = try encoder.encode(calculator.mcpTools)
	let jsonString = String(data: jsonData, encoding: .utf8)
	
	print(jsonString!)
	
	// The standard JSONEncoder now properly handles numeric and boolean default values
	print("\nJSON with properly typed default values:")
	print(jsonString!)
}

// Run the async function
Task {
    do {
        try await run()
    } catch {
        print("Error: \(error)")
    }
    
    // Exit the program when done
    exit(0)
}

// Keep the main thread alive
dispatchMain() 
