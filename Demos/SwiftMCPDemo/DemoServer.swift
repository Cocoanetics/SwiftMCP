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

    /// Gets the current date/time on the server
    /// - Returns: The current time
    @MCPTool(hints: [.readOnly])
    func getCurrentDateTime() async -> Date {
        await Self.logCall(function: "getCurrentDateTime")
        return Date()
    }

    /// Returns a mock weather report for the supplied location.
    /// - Parameter location: City name or zip code
    /// - Returns: A weather report
    @MCPTool(hints: [.readOnly, .openWorld])
    func getWeatherReport(location: String) async -> WeatherReport {
        await Self.logCall(function: "getWeatherReport", arguments: ["location": location])
        return WeatherReport(temperature: 22.5, conditions: "Partly cloudy", humidity: 65, location: location)
    }

    /// Formats a date/time as String
    /// - Parameter date: The Date to format
    /// - Returns: A string with the date formatted
    @MCPTool(hints: [.readOnly, .idempotent])
    func formatDateAsString(date: Date) async -> String {
        await Self.logCall(function: "formatDateAsString", arguments: ["date": date])
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .long
        dateFormatter.timeStyle = .long
        return dateFormatter.string(from: date)
    }

    /// Adds the specified number of hours to a date and returns the result.
    /// - Parameter date: The starting date
    /// - Parameter hours: Hours to add
    /// - Returns: The adjusted date
    @MCPTool(hints: [.readOnly, .idempotent])
    func addHours(date: Date, hours: Int) async -> Date {
        await Self.logCall(function: "addHours", arguments: ["hours": hours])
        return date.addingTimeInterval(TimeInterval(hours * 3600))
    }

    /// Returns the normalized URL by removing fragments and resolving the path.
    /// - Parameter url: The URL to normalize
    /// - Returns: The normalized URL
    @MCPTool(hints: [.readOnly, .idempotent])
    func normalizeURL(url: URL) async -> URL {
        await Self.logCall(function: "normalizeURL", arguments: ["url": url.absoluteString])
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        components?.fragment = nil
        return components?.url ?? url
    }

    /// Returns the same UUID after logging it, demonstrating UUID round-tripping.
    /// - Parameter uuid: The UUID to round-trip
    /// - Returns: The same UUID
    @MCPTool(hints: [.readOnly, .idempotent])
    func roundTripUUID(uuid: UUID) async -> UUID {
        await Self.logCall(function: "roundTripUUID", arguments: ["uuid": uuid.uuidString])
        return uuid
    }

    /// Returns the same data after logging its size, demonstrating byte-string encoding.
    /// - Parameter data: The data to round-trip
    /// - Returns: The same data
    @MCPTool(hints: [.readOnly, .idempotent])
    func roundTripData(data: Data) async -> Data {
        await Self.logCall(function: "roundTripData", arguments: ["byteCount": data.count])
        return data
    }

    /// Adds two integers and returns their sum
    /// - Parameter a: First number to add
    /// - Parameter b: Second number to add
    /// - Returns: The sum of a and b
    @MCPTool(description: "Custom description: Performs addition of two numbers", hints: [.readOnly, .idempotent])
    // swiftlint:disable:next identifier_name
    func add(a: Int, b: Int) async -> Int {
        await Self.logCall(function: "add", arguments: ["a": a, "b": b])
        return a + b
    }

    /// Subtracts the second integer from the first and returns the difference
    /// - Parameter a: Number to subtract from
    /// - Parameter b: Number to subtract
    /// - Returns: The difference between a and b
    @MCPTool(hints: [.readOnly, .idempotent])
    // swiftlint:disable:next identifier_name
    func subtract(a: Int = 5, b: Int = 3) async -> Int {
        await Self.logCall(function: "subtract", arguments: ["a": a, "b": b])
        return a - b
    }

    /// Tests array processing
    /// - Parameter a: Array of integers to process
    /// - Returns: A string representation of the array
    @MCPTool(description: "Custom description: Tests array processing", hints: [.readOnly, .idempotent])
    // swiftlint:disable:next identifier_name
    func testArray(a: [Int] = [1, 2, 3]) async -> String {
        await Self.logCall(function: "testArray", arguments: ["a": a])
        return a.map(String.init).joined(separator: ", ")
    }

    /// Multiplies two integers and returns their product
    /// - Parameter a: First factor
    /// - Parameter b: Second factor
    /// - Returns: The product of a and b
    @MCPTool(hints: [.readOnly, .idempotent])
    // swiftlint:disable:next identifier_name
    func multiply(a: Int, b: Int) async -> Int {
        await Self.logCall(function: "multiply", arguments: ["a": a, "b": b])
        return a * b
    }

    /// Divides the numerator by the denominator and returns the quotient
    /// - Parameter numerator: Number to be divided
    /// - Parameter denominator: Number to divide by (defaults to 1.0)
    /// - Returns: The quotient of numerator divided by denominator
    @MCPTool(hints: [.readOnly, .idempotent])
    func divide(numerator: Double, denominator: Double = 1.0) async -> Double {
        await Self.logCall(function: "divide", arguments: ["numerator": numerator, "denominator": denominator])
        return numerator / denominator
    }

    /// Returns a greeting message with the provided name
    /// - Parameter name: Name of the person to greet
    /// - Returns: The greeting message
    @MCPTool(description: "Shows a greeting message", hints: [.readOnly, .idempotent])
    func greet(name: String) async throws -> String {
        await Self.logCall(function: "greet", arguments: ["name": name])
        if name.count < 2 {
            throw DemoError.nameTooShort(name: name)
        }
        if !name.allSatisfy({ $0.isLetter || $0.isWhitespace }) {
            throw DemoError.invalidName(name: name)
        }
        return "Hello, \(name)!"
    }

    /** A simple ping function that returns 'pong' */
    @MCPTool(hints: [.readOnly, .idempotent])
    func ping() async -> String {
        await Self.logCall(function: "ping")
        return "pong"
    }

    /** A function to test doing nothing, not returning anything*/
    @MCPTool(hints: [.readOnly, .idempotent])
    func noop() async {
        await Self.logCall(function: "noop")
    }

    /**
     Performs a 30-second countdown with progress notifications every second.
	 
     This function demonstrates long-running operations with progress tracking.
     It counts down from 30 to 0, sending a progress notification each second.
	 
     - Returns: A completion message
     */
    @MCPTool(description: "Performs a 30-second countdown with progress updates", hints: [.readOnly, .idempotent])
    func countdown() async -> String {
        await Self.logCall(function: "countdown", arguments: ["message": "Starting 30-second countdown"])
        let totalSeconds = 30
        for second in (0...totalSeconds).reversed() {
            let progress = Double(totalSeconds - second) / Double(totalSeconds)
            let message = second == 0 ? "Countdown complete!" : "\(second) seconds remaining"
            await RequestContext.current?.reportProgress(progress, total: 1.0, message: message)
            if second > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
            }
        }
        await Self.logCall(function: "countdown", arguments: ["message": "Countdown completed successfully"])
        return "Countdown completed! 🎉"
    }

    /** A function returning a random image
     - returns: A small PNG file */
    @MCPTool(hints: [.readOnly])
    func randomImage() async -> MCPImage {
        await Self.logCall(function: "randomImage")
        let base64PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+X2WkAAAAASUVORK5CYII="
        let data = Data(base64Encoded: base64PNG) ?? Data()
        return MCPImage(data: data, mimeType: "image/png")
    }

    // MARK: - Resources

    /// Returns a static server info string
    @MCPResource("server://info")
    func getServerInfo() async -> String {
        await Self.logCall(function: "getServerInfo")
        return "SwiftMCP Demo Server v1.0"
    }

    /// Returns a greeting for a user by ID
    /// - Parameter user_id: The user's unique identifier
    @MCPResource("users://{user_id}/greeting")
    // swiftlint:disable:next identifier_name
    func getUserGreeting(user_id: Int) async -> String {
        await Self.logCall(function: "getUserGreeting", arguments: ["user_id": user_id])
        return "Hello, user #\(user_id)!"
    }

    /// Searches users with a query and optional page/limit
    /// - Parameters:
    ///   - query: The search query
    ///   - page: The page number (default: 1)
    ///   - limit: The number of results per page (default: 10)
    @MCPResource("search://users?query={query}&page={page}&limit={limit}")
    func searchUsers(query: String, page: Int = 1, limit: Int = 10) async throws -> String {
        await Self.logCall(function: "searchUsers", arguments: ["query": query, "page": page, "limit": limit])
        return "Results for query '\(query)' (page \(page), limit \(limit))"
    }

    /// Returns a list of available features
    @MCPResource("features://list", name: "Features.list")
    func getFeatureList() async -> [String] {
        await Self.logCall(function: "getFeatureList")
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
        await Self.logCall(function: "getColorMessage", arguments: ["color": color, "bool": bool])
        return Self.message(for: color)
    }

    // MARK: - Prompts

    /// A prompt for saying Hello
    @MCPPrompt()
    func helloPrompt(name: String) async throws -> [PromptMessage] {
        await Self.logCall(function: "helloPrompt", arguments: ["name": name])
        return [PromptMessage(role: .assistant, content: .init(text: "Hello \(name)!"))]
    }

    /// A prompt to get a color description
    /// - parameter color: A color
    @MCPPrompt()
    func colorPrompt(color: Color) async -> String {
        await Self.logCall(function: "colorPrompt", arguments: ["color": color])
        return Self.message(for: color)
    }

    // MARK: - Sampling

    /// Requests sampling from the client using the MCP Sampling feature.
    /// - Parameter prompt: The prompt to send to the client's LLM
    /// - Parameter modelPreferences: Optional model preferences for the request
    /// - Returns: The generated text from the client, or nil if no context is available
    @MCPTool(description: "Requests sampling from the client LLM", hints: [.readOnly, .openWorld])
    func sampleFromClient(prompt: String, modelPreferences: ModelPreferences? = nil) async throws -> String {
        await Self.logCall(
            function: "sampleFromClient",
            arguments: ["prompt": prompt, "has_model_preferences": modelPreferences != nil]
        )
        return try await RequestContext.current?.sample(
            prompt: prompt, modelPreferences: modelPreferences
        ) ?? "No response from client"
    }

    // MARK: - Elicitation

    /// Requests basic contact information from the user using the MCP Elicitation feature.
    /// - Returns: A string describing the user's response or the action they took
    @MCPTool(description: "Requests contact information from the user", hints: [.readOnly, .openWorld])
    func requestContactInfo() async throws -> String {
        await Self.logCall(function: "requestContactInfo")
        let response = try await RequestContext.current?.elicit(
            message: "Please provide your contact information",
            schema: Self.makeContactInfoSchema()
        )
        guard let elicitationResponse = response else { return "No elicitation response received" }
        return Self.describeContactResponse(elicitationResponse)
    }

    /// Requests project preferences from the user using predefined options.
    /// - Returns: A string describing the user's project preferences or their action
    @MCPTool(description: "Requests project preferences from the user", hints: [.readOnly, .openWorld])
    func requestProjectPreferences() async throws -> String {
        await Self.logCall(function: "requestProjectPreferences")
        let response = try await RequestContext.current?.elicit(
            message: "Please tell us about your project preferences",
            schema: Self.makeProjectPreferencesSchema()
        )
        guard let elicitationResponse = response else { return "No elicitation response received" }
        return Self.describeProjectPreferencesResponse(elicitationResponse)
    }

    /// Requests user credentials with validation constraints.
    /// - Returns: A string describing the user's response or the action they took
    @MCPTool(description: "Requests user credentials with validation", hints: [.readOnly, .openWorld])
    func requestUserCredentials() async throws -> String {
        await Self.logCall(function: "requestUserCredentials")
        let response = try await RequestContext.current?.elicit(
            message: "Please create your account credentials",
            schema: Self.makeUserCredentialsSchema()
        )
        guard let elicitationResponse = response else { return "No elicitation response received" }
        return Self.describeUserCredentialsResponse(elicitationResponse)
    }

    /// Requests user preferences with enum options and display names.
    /// - Returns: A string describing the user's response or the action they took
    @MCPTool(description: "Requests user preferences with enum options", hints: [.readOnly, .openWorld])
    func requestUserPreferences() async throws -> String {
        await Self.logCall(function: "requestUserPreferences")
        let response = try await RequestContext.current?.elicit(
            message: "Please configure your preferences",
            schema: Self.makeUserPreferencesSchema()
        )
        guard let elicitationResponse = response else { return "No elicitation response received" }
        return Self.describeUserPreferencesResponse(elicitationResponse)
    }

    // MARK: - Notifications

    /// Handles the roots list changed notification by retrieving and logging the updated roots.
    func handleRootsListChanged() async {
        guard let session = Session.current else { return }
        do {
            let updatedRoots = try await session.listRoots()
            await session.sendLogNotification(LogMessage(
                level: .info,
                data: ["message": "Roots list updated", "roots": updatedRoots]
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
