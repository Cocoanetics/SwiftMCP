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
	func getCurrentDateTime() async -> Date {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "getCurrentDateTime called"))
		return Date()
	}
	
	/**
	 Formats a date/time as String
	 - Parameter date: The Date to format
	 - Returns: A string with the date formatted
	 */
	@MCPTool(isConsequential: false)
	func formatDateAsString(date: Date) async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "formatDateAsString called with date=\(date)"))
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
	func add(a: Int, b: Int) async -> Int {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "add called with a=\(a), b=\(b)"))
		return a + b
	}
	
	/// Subtracts the second integer from the first and returns the difference
	/// - Parameter a: Number to subtract from
	/// - Parameter b: Number to subtract
	/// - Returns: The difference between a and b
	@MCPTool
	func subtract(a: Int = 5, b: Int = 3) async -> Int {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "subtract called with a=\(a), b=\(b)"))
		return a - b
	}
	
	/**
	 Tests array processing
	 - Parameter a: Array of integers to process
	 - Returns: A string representation of the array
	 */
	@MCPTool(description: "Custom description: Tests array processing")
	func testArray(a: [Int] = [1,2,3]) async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "testArray called with a=\(a)"))
		return a.map(String.init).joined(separator: ", ")
	}
	
	/**
	 Multiplies two integers and returns their product
	 - Parameter a: First factor
	 - Parameter b: Second factor
	 - Returns: The product of a and b
	 */
	@MCPTool
	func multiply(a: Int, b: Int) async -> Int {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "multiply called with a=\(a), b=\(b)"))
		return a * b
	}
	
	/// Divides the numerator by the denominator and returns the quotient
	/// - Parameter numerator: Number to be divided
	/// - Parameter denominator: Number to divide by (defaults to 1.0)
	/// - Returns: The quotient of numerator divided by denominator
	@MCPTool
	func divide(numerator: Double, denominator: Double = 1.0) async -> Double {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "divide called with numerator=\(numerator), denominator=\(denominator)"))
		return numerator / denominator
	}
	
	/// Returns a greeting message with the provided name
	/// - Parameter name: Name of the person to greet
	/// - Returns: The greeting message
	@MCPTool(description: "Shows a greeting message")
	func greet(name: String) async throws -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "greet called with name=\(name)"))
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
	func ping() async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "ping called"))
		return "pong"
	}
	
	/** A function to test doing nothing, not returning anything*/
	@MCPTool
	func noop() async {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "noop called"))
	}
	
	/** A function returning a random file
	 - returns: A multiple simple text files */
	@MCPTool
	func randomFile() async -> [FileResourceContent]
	{
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "randomFile called"))
		return [FileResourceContent(uri: URL(string: "file:///hello.txt")!, mimeType: "text/plain", text: "Hello World!"),
				FileResourceContent(uri: URL(string: "file:///hello2.txt")!, mimeType: "text/plain", text: "Hello World 2!")]
	}
	
	/// Returns a static server info string
	@MCPResource("server://info")
	func getServerInfo() async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "getServerInfo called"))
		return "SwiftMCP Demo Server v1.0"
	}
	
	/// Returns a greeting for a user by ID
	/// - Parameter user_id: The user's unique identifier
	@MCPResource("users://{user_id}/greeting")
	func getUserGreeting(user_id: Int) async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "getUserGreeting called with user_id=\(user_id)"))
		return "Hello, user #\(user_id)!"
	}
	
	/// Searches users with a query and optional page/limit
	/// - Parameters:
	///   - query: The search query
	///   - page: The page number (default: 1)
	///   - limit: The number of results per page (default: 10)
	@MCPResource("search://users?query={query}&page={page}&limit={limit}")
	func searchUsers(query: String, page: Int = 1, limit: Int = 10) async throws -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "searchUsers called with query=\(query), page=\(page), limit=\(limit)"))
		return "Results for query '\(query)' (page \(page), limit \(limit))"
	}
	
	/// Returns a list of available features
	@MCPResource("features://list", name: "Features.list")
	func getFeatureList() async -> [String] {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "getFeatureList called"))
		return ["math", "date", "greet", "file"]
	}
	
	// Example enum that is only CaseIterable
	enum Color: CaseIterable {
		case red
		case green
		case blue
	}
	
	/// Returns a message for the selected color
	@MCPResource("color://message?color={color}&bool={bool}")
    func getColorMessage(color: Color, bool: Bool) async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, message: "getColorMessage called with color=\(color), bool=\(bool)"))
		switch color {
			case .red:
				return "You selected RED!"
			case .green:
				return "You selected GREEN!"
			case .blue:
				return "You selected BLUE!"
		}
	}
    
    /// A prompt for saying Hello
    @MCPPrompt()
    func helloPrompt(name: String) async throws -> [PromptMessage] {
        await Session.current?.sendLogNotification(LogMessage(level: .info, message: "helloPrompt called with name=\(name)"))
        let message = PromptMessage(role: .assistant, content: .init(text: "Hello \(name)!"))
        return [message]
    }
    
    /// A prompt to get a color description
    /// - parameter color: A color
    @MCPPrompt()
    func colorPrompt(color: Color) async -> String {
        await Session.current?.sendLogNotification(LogMessage(level: .info, message: "colorPrompt called with color=\(color)"))
        let text: String
        
        switch color {
            case .red:
                text = "You selected RED!"
            case .green:
                text = "You selected GREEN!"
            case .blue:
                text = "You selected BLUE!"
        }
        
        return text
    }
}

