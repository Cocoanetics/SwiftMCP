import Foundation
import SwiftMCP

/**
 A Calculator for simple math doing additionals, subtractions etc.
 
 Testing "quoted" stuff. And on multiple lines. 'single quotes'
 */
@MCPServer(name: "SwiftMCP Demo")
actor DemoServer {
	
	/**
	 Gets the current date/time on the server
	 - Returns: The current time
	 */
	@MCPTool
	func getCurrentDateTime() -> Date {
		return Date()
	}
	
	/**
	 Formats a date/time as String
	 - Parameter date: The Date to format
	 - Returns: A string with the date formatted
	 */
	@MCPTool(isConsequential: false)
	func formatDateAsString(date: Date) -> String {
		
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .long
		dateFormatter.timeStyle = .long
		
		return dateFormatter.string(from: date)
	}
	
	/// Adds two integers and returns their sum
	/// - Parameter a: First number to add
	/// - Parameter b: Second number to add
	/// - Returns: The sum of a and b
	@MCPTool(description: "Custom description: Performs addition of two numbers")
	func add(a: Int, b: Int) -> Int {
		return a + b
	}
	
	/// Subtracts the second integer from the first and returns the difference
	/// - Parameter a: Number to subtract from
	/// - Parameter b: Number to subtract
	/// - Returns: The difference between a and b
	@MCPTool
	func subtract(a: Int = 5, b: Int = 3) -> Int {
		return a - b
	}
	
	/**
	 Tests array processing
	 - Parameter a: Array of integers to process
	 - Returns: A string representation of the array
	 */
	@MCPTool(description: "Custom description: Tests array processing")
	func testArray(a: [Int] = [1,2,3]) -> String {
		return a.map(String.init).joined(separator: ", ")
	}
	
	/**
	 Multiplies two integers and returns their product
	 - Parameter a: First factor
	 - Parameter b: Second factor
	 - Returns: The product of a and b
	 */
	@MCPTool
	func multiply(a: Int, b: Int) -> Int {
		return a * b
	}
	
	/// Divides the numerator by the denominator and returns the quotient
	/// - Parameter numerator: Number to be divided
	/// - Parameter denominator: Number to divide by (defaults to 1.0)
	/// - Returns: The quotient of numerator divided by denominator
	@MCPTool
	func divide(numerator: Double, denominator: Double = 1.0) -> Double {
		return numerator / denominator
	}
	
	/// Returns a greeting message with the provided name
	/// - Parameter name: Name of the person to greet
	/// - Returns: The greeting message
	@MCPTool(description: "Shows a greeting message")
	func greet(name: String) async throws -> String {
		// Validate name length
		if name.count < 2 {
			throw DemoError.nameTooShort(name: name)
		}
		
		// Validate name contains only letters and spaces
		if !name.allSatisfy({ $0.isLetter || $0.isWhitespace }) {
			throw DemoError.invalidName(name: name)
		}
		
		return "Hello, \(name)!"
	}
	
	
	/** A simple ping function that returns 'pong' */
	@MCPTool
	func ping() -> String {
		return "pong"
	}
	
	/** A function to test doing nothing, not returning anything*/
	@MCPTool
	func noop() {
		
	}
}

