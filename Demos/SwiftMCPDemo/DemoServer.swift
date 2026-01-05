import Foundation
import SwiftMCP

/// A simple weather report response
@Schema
struct WeatherReport: Sendable, Codable {
	/// Temperature in celsius
	let temperature: Double
	/// Weather conditions description
	let conditions: String
	/// Humidity percentage
	let humidity: Double
	/// Location for the report
	let location: String
}

/**
 A Calculator for simple math doing additionals, subtractions etc.
 
 Testing "quoted" stuff. And on multiple lines. 'single quotes'
 */
@MCPServer(name: "SwiftMCP Demo", generateClient: true)
actor DemoServer {
	
    // MARK: - Tools
    
	/**
	 Gets the current date/time on the server
	 - Returns: The current time
	 */
	@MCPTool
	func getCurrentDateTime() async -> Date {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "getCurrentDateTime",
			"message": "getCurrentDateTime called"
		]))
		return Date()
	}

	/**
	 Returns a mock weather report for the supplied location.
	 - Parameter location: City name or zip code
	 - Returns: A weather report
	 */
	@MCPTool
	func getWeatherReport(location: String) async -> WeatherReport {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "getWeatherReport",
			"location": location
		]))
		return WeatherReport(
			temperature: 22.5,
			conditions: "Partly cloudy",
			humidity: 65,
			location: location
		)
	}
	
	/**
	 Formats a date/time as String
	 - Parameter date: The Date to format
	 - Returns: A string with the date formatted
	 */
	@MCPTool(isConsequential: false)
	func formatDateAsString(date: Date) async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "formatDateAsString",
			"date": date,
			"timestamp": date.timeIntervalSince1970
		]))
		let dateFormatter = DateFormatter()
		dateFormatter.dateStyle = .long
		dateFormatter.timeStyle = .long
		
		return dateFormatter.string(from: date)
	}

	/**
	 Adds the specified number of hours to a date and returns the result.
	 - Parameter date: The starting date
	 - Parameter hours: Hours to add
	 - Returns: The adjusted date
	 */
	@MCPTool
	func addHours(date: Date, hours: Int) async -> Date {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "addHours",
			"hours": hours
		]))
		let seconds = TimeInterval(hours * 3600)
		return date.addingTimeInterval(seconds)
	}

	/**
	 Returns the normalized URL by removing fragments and resolving the path.
	 - Parameter url: The URL to normalize
	 - Returns: The normalized URL
	 */
	@MCPTool
	func normalizeURL(url: URL) async -> URL {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "normalizeURL",
			"url": url.absoluteString
		]))
		var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
		components?.fragment = nil
		return components?.url ?? url
	}

	/**
	 Returns the same UUID after logging it, demonstrating UUID round-tripping.
	 - Parameter uuid: The UUID to round-trip
	 - Returns: The same UUID
	 */
	@MCPTool
	func roundTripUUID(uuid: UUID) async -> UUID {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "roundTripUUID",
			"uuid": uuid.uuidString
		]))
		return uuid
	}

	/**
	 Returns the same data after logging its size, demonstrating byte-string encoding.
	 - Parameter data: The data to round-trip
	 - Returns: The same data
	 */
	@MCPTool
	func roundTripData(data: Data) async -> Data {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "roundTripData",
			"byteCount": data.count
		]))
		return data
	}
	
	/// Adds two integers and returns their sum
	/// - Parameter a: First number to add
	/// - Parameter b: Second number to add
	/// - Returns: The sum of a and b
	@MCPTool(description: "Custom description: Performs addition of two numbers")
	func add(a: Int, b: Int) async -> Int {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "add",
			"message": "add called",
			"arguments": ["a": a, "b": b]
		]))
		return a + b
	}
	
	/// Subtracts the second integer from the first and returns the difference
	/// - Parameter a: Number to subtract from
	/// - Parameter b: Number to subtract
	/// - Returns: The difference between a and b
	@MCPTool
	func subtract(a: Int = 5, b: Int = 3) async -> Int {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "subtract",
			"message": "subtract called",
			"arguments": ["a": a, "b": b]
		]))
		return a - b
	}
	
	/**
	 Tests array processing
	 - Parameter a: Array of integers to process
	 - Returns: A string representation of the array
	 */
	@MCPTool(description: "Custom description: Tests array processing")
	func testArray(a: [Int] = [1,2,3]) async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "testArray",
			"message": "testArray called",
			"arguments": ["a": a]
		]))
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
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "multiply",
			"message": "multiply called",
			"arguments": ["a": a, "b": b]
		]))
		return a * b
	}
	
	/// Divides the numerator by the denominator and returns the quotient
	/// - Parameter numerator: Number to be divided
	/// - Parameter denominator: Number to divide by (defaults to 1.0)
	/// - Returns: The quotient of numerator divided by denominator
	@MCPTool
	func divide(numerator: Double, denominator: Double = 1.0) async -> Double {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "divide",
			"message": "divide called",
			"arguments": ["numerator": numerator, "denominator": denominator]
		]))
		return numerator / denominator
	}
	
	/// Returns a greeting message with the provided name
	/// - Parameter name: Name of the person to greet
	/// - Returns: The greeting message
	@MCPTool(description: "Shows a greeting message")
	func greet(name: String) async throws -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "greet",
			"message": "greet called",
			"arguments": ["name": name]
		]))
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
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "ping",
			"message": "ping called"
		]))
		return "pong"
	}
	
	/** A function to test doing nothing, not returning anything*/
	@MCPTool
	func noop() async {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "noop",
			"message": "noop called"
		]))
	}
	
	/**
	 Performs a 30-second countdown with progress notifications every second.
	 
	 This function demonstrates long-running operations with progress tracking.
	 It counts down from 30 to 0, sending a progress notification each second.
	 
	 - Returns: A completion message
	 */
	@MCPTool(description: "Performs a 30-second countdown with progress updates")
	func countdown() async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "countdown",
			"message": "Starting 30-second countdown"
		]))
		
		let totalSeconds = 30
		
		for second in (0...totalSeconds).reversed() {
			let progress = Double(totalSeconds - second) / Double(totalSeconds)
			let message = second == 0 ? "Countdown complete!" : "\(second) seconds remaining"
			
			await RequestContext.current?.reportProgress(progress, total: 1.0, message: message)
			
			if second > 0 {
				try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
			}
		}
		
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "countdown",
			"message": "Countdown completed successfully"
		]))
		
		return "Countdown completed! 🎉"
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
	
    // MARK: - Resources
    
	/// Returns a static server info string
	@MCPResource("server://info")
	func getServerInfo() async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "getServerInfo",
			"message": "getServerInfo called"
		]))
		return "SwiftMCP Demo Server v1.0"
	}
	
	/// Returns a greeting for a user by ID
	/// - Parameter user_id: The user's unique identifier
	@MCPResource("users://{user_id}/greeting")
	func getUserGreeting(user_id: Int) async -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "getUserGreeting",
			"message": "getUserGreeting called",
			"arguments": ["user_id": user_id]
		]))
		return "Hello, user #\(user_id)!"
	}
	
	/// Searches users with a query and optional page/limit
	/// - Parameters:
	///   - query: The search query
	///   - page: The page number (default: 1)
	///   - limit: The number of results per page (default: 10)
	@MCPResource("search://users?query={query}&page={page}&limit={limit}")
	func searchUsers(query: String, page: Int = 1, limit: Int = 10) async throws -> String {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "searchUsers",
			"message": "searchUsers called",
			"arguments": ["query": query, "page": page, "limit": limit]
		]))
		return "Results for query '\(query)' (page \(page), limit \(limit))"
	}
	
	/// Returns a list of available features
	@MCPResource("features://list", name: "Features.list")
	func getFeatureList() async -> [String] {
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "getFeatureList",
			"message": "getFeatureList called"
		]))
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
		await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
			"function": "getColorMessage",
			"message": "getColorMessage called",
			"arguments": ["color": color, "bool": bool]
		]))
		switch color {
			case .red:
				return "You selected RED!"
			case .green:
				return "You selected GREEN!"
			case .blue:
				return "You selected BLUE!"
		}
	}
    
    // MARK: - Prompts
    
    /// A prompt for saying Hello
    @MCPPrompt()
    func helloPrompt(name: String) async throws -> [PromptMessage] {
        await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
            "function": "helloPrompt",
            "message": "helloPrompt called",
            "arguments": ["name": name]
        ]))
        let message = PromptMessage(role: .assistant, content: .init(text: "Hello \(name)!"))
        return [message]
    }
    
    /// A prompt to get a color description
    /// - parameter color: A color
    @MCPPrompt()
    func colorPrompt(color: Color) async -> String {
        await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
            "function": "colorPrompt",
            "message": "colorPrompt called",
            "arguments": ["color": color]
        ]))
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
    
    // MARK: - Sampling

    /**
     Requests sampling from the client using the MCP Sampling feature.
     - Parameter prompt: The prompt to send to the client's LLM
     - Parameter modelPreferences: Optional model preferences for the request
     - Returns: The generated text from the client, or nil if no context is available
     */
    @MCPTool(description: "Requests sampling from the client LLM")
    func sampleFromClient(prompt: String, modelPreferences: ModelPreferences? = nil) async throws -> String {
        await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
            "function": "sampleFromClient",
            "message": "sampleFromClient called",
            "arguments": ["prompt": prompt, "has_model_preferences": modelPreferences != nil]
        ]))
        
        return try await RequestContext.current?.sample(prompt: prompt, modelPreferences: modelPreferences) ?? "No response from client"
    }

    // MARK: - Elicitation

    /**
     Requests basic contact information from the user using the MCP Elicitation feature.
     - Returns: A string describing the user's response or the action they took
     */
    @MCPTool(description: "Requests contact information from the user")
    func requestContactInfo() async throws -> String {
        await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
            "function": "requestContactInfo",
            "message": "requestContactInfo called"
        ]))
        
        // Create a schema for contact information
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: [
                "name": .string(title: "Full Name", description: "Your full name", format: nil, minLength: 2, maxLength: 50),
                "email": .string(title: "Email Address", description: "Your email address", format: "email", minLength: nil, maxLength: nil),
                "age": .number(title: "Age", description: "Your age", minimum: 13, maximum: 120)
            ],
            required: ["name", "email"],
            title: "Contact Information",
            description: "Basic contact details"
        ))
        
        let response = try await RequestContext.current?.elicit(
            message: "Please provide your contact information",
            schema: schema
        )
        
        guard let elicitationResponse = response else {
            return "No elicitation response received"
        }
        
        switch elicitationResponse.action {
        case .accept:
            if let content = elicitationResponse.content {
                let name = content["name"]?.value as? String ?? "Unknown"
                let email = content["email"]?.value as? String ?? "Unknown"
                let age = content["age"]?.value as? Double ?? 0
                return "Thank you! Contact info received: \(name) (\(email)), age: \(Int(age))"
            } else {
                return "User accepted but no content was provided"
            }
        case .decline:
            return "User declined to provide contact information"
        case .cancel:
            return "User cancelled the contact information request"
        }
    }
    
    /**
     Requests project preferences from the user using predefined options.
     - Returns: A string describing the user's project preferences or their action
     */
    @MCPTool(description: "Requests project preferences from the user")
    func requestProjectPreferences() async throws -> String {
        await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
            "function": "requestProjectPreferences",
            "message": "requestProjectPreferences called"
        ]))
        
        // Create a schema for project preferences with enum values
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: [
                "projectType": .enum(values: ["web", "mobile", "desktop", "api"], description: "Type of project"),
                "framework": .string(description: "Preferred framework or technology"),
                "priority": .enum(values: ["speed", "cost", "quality"], description: "Main priority for the project"),
                "hasDeadline": .boolean(description: "Whether the project has a specific deadline")
            ],
            required: ["projectType", "priority"],
            description: "Project preferences and requirements"
        ))
        
        let response = try await RequestContext.current?.elicit(
            message: "Please tell us about your project preferences",
            schema: schema
        )
        
        guard let elicitationResponse = response else {
            return "No elicitation response received"
        }
        
        switch elicitationResponse.action {
        case .accept:
            if let content = elicitationResponse.content {
                let projectType = content["projectType"]?.value as? String ?? "unspecified"
                let framework = content["framework"]?.value as? String ?? "not specified"
                let priority = content["priority"]?.value as? String ?? "unspecified"
                let hasDeadline = content["hasDeadline"]?.value as? Bool ?? false
                
                return "Project preferences received: \(projectType) project using \(framework), prioritizing \(priority)" + 
                       (hasDeadline ? " with a deadline" : " without a specific deadline")
            } else {
                return "User accepted but no content was provided"
            }
        case .decline:
            return "User declined to provide project preferences"
        case .cancel:
            return "User cancelled the project preferences request"
        }
    }
    
    /**
     Requests user credentials with validation constraints.
     - Returns: A string describing the user's response or the action they took
     */
    @MCPTool(description: "Requests user credentials with validation")
    func requestUserCredentials() async throws -> String {
        await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
            "function": "requestUserCredentials",
            "message": "requestUserCredentials called"
        ]))
        
        // Create a schema with string length constraints and boolean defaults
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: [
                "username": .string(title: "Username", description: "Username (3-20 characters)", format: nil, minLength: 3, maxLength: 20),
                "password": .string(title: "Password", description: "Password (8-50 characters)", format: nil, minLength: 8, maxLength: 50),
                "confirmPassword": .string(title: "Confirm Password", description: "Confirm password", format: nil, minLength: 8, maxLength: 50),
                "email": .string(title: "Email", description: "Email address", format: "email", minLength: 5, maxLength: 100),
                "agreeToTerms": .boolean(title: "Terms & Conditions", description: "I agree to the terms and conditions", defaultValue: false),
                "receiveNewsletter": .boolean(title: "Newsletter", description: "Receive newsletter updates", defaultValue: true)
            ],
            required: ["username", "password", "confirmPassword", "email", "agreeToTerms"],
            title: "Account Registration",
            description: "User credentials with validation constraints"
        ))
        
        let response = try await RequestContext.current?.elicit(
            message: "Please create your account credentials",
            schema: schema
        )
        
        guard let elicitationResponse = response else {
            return "No elicitation response received"
        }
        
        switch elicitationResponse.action {
        case .accept:
            if let content = elicitationResponse.content {
                let username = content["username"]?.value as? String ?? "Unknown"
                let email = content["email"]?.value as? String ?? "Unknown"
                let password = content["password"]?.value as? String ?? ""
                let confirmPassword = content["confirmPassword"]?.value as? String ?? ""
                
                // Basic validation example
                if password == confirmPassword {
                    return "Account creation successful! Username: \(username), Email: \(email)"
                } else {
                    return "Password mismatch detected. Please try again."
                }
            } else {
                return "User accepted but no content was provided"
            }
        case .decline:
            return "User declined to create account"
        case .cancel:
            return "User cancelled the account creation"
        }
    }
    
    /**
     Requests user preferences with enum options and display names.
     - Returns: A string describing the user's response or the action they took
     */
    @MCPTool(description: "Requests user preferences with enum options")
    func requestUserPreferences() async throws -> String {
        await Session.current?.sendLogNotification(LogMessage(level: .info, data: [
            "function": "requestUserPreferences",
            "message": "requestUserPreferences called"
        ]))
        
        // Create a schema with enum values and display names
        let schema = JSONSchema.object(JSONSchema.Object(
            properties: [
                "theme": .enum(
                    values: ["light", "dark", "auto"],
                    title: "Theme Preference",
                    description: "Choose your preferred theme",
                    enumNames: ["Light Mode", "Dark Mode", "Auto (System)"]
                ),
                "language": .enum(
                    values: ["en", "es", "fr", "de", "ja"],
                    title: "Language",
                    description: "Select your preferred language",
                    enumNames: ["English", "Español", "Français", "Deutsch", "日本語"]
                ),
                "notifications": .boolean(
                    title: "Enable Notifications",
                    description: "Receive push notifications",
                    defaultValue: true
                ),
                "maxItems": .number(
                    title: "Max Items per Page",
                    description: "Number of items to display per page",
                    minimum: 10,
                    maximum: 100
                )
            ],
            required: ["theme", "language"],
            title: "User Preferences",
            description: "Customize your application experience"
        ))
        
        let response = try await RequestContext.current?.elicit(
            message: "Please configure your preferences",
            schema: schema
        )
        
        guard let elicitationResponse = response else {
            return "No elicitation response received"
        }
        
        switch elicitationResponse.action {
        case .accept:
            if let content = elicitationResponse.content {
                let theme = content["theme"]?.value as? String ?? "unknown"
                let language = content["language"]?.value as? String ?? "unknown"
                let notifications = content["notifications"]?.value as? Bool ?? false
                let maxItems = content["maxItems"]?.value as? Double ?? 25.0
                
                return "Preferences saved! Theme: \(theme), Language: \(language), Notifications: \(notifications), Max items: \(Int(maxItems))"
            } else {
                return "User accepted but no content was provided"
            }
        case .decline:
            return "User declined to set preferences"
        case .cancel:
            return "User cancelled preference configuration"
        }
    }

    // MARK: - Notifications
    
    /**
     Handles the roots list changed notification from the client.
     
     This implementation retrieves the updated list of roots from the client session
     whenever a 'roots/list_changed' notification is received. It then logs the new
     list of roots (including their URIs and names) for debugging and verification.
     If an error occurs while retrieving the roots, it logs a warning with the error message.
     */
    func handleRootsListChanged() async {
        guard let session = Session.current else { return }
        do {
            let updatedRoots = try await session.listRoots()
            await session.sendLogNotification(LogMessage(
                level: .info,
                data: [
                    "message": "Roots list updated",
                    "roots": updatedRoots
                ]
            ))
        } catch {
            await session.sendLogNotification(LogMessage(
                level: .warning,
                data: [
                    "message": "Failed to retrieve updated roots list",
                    "error": error.localizedDescription
                ]
            ))
        }
    }
}
