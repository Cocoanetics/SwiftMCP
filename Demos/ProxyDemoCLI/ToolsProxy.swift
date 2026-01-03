import Foundation
import SwiftMCP
public actor SwiftMCPDemoProxy {
    // MARK: - Public Properties
    public let proxy: MCPServerProxy

    // MARK: - Initialization
    public init(proxy: MCPServerProxy) {
        self.proxy = proxy
    }

    // MARK: - Functions

    /**
     Custom description: Performs addition of two numbers
     - Parameter a: First number to add
     - Parameter b: Second number to add
     */
    public func add(a: Double, b: Double) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["a"] = a
        arguments["b"] = b
        let text = try await proxy.callTool("add", arguments: arguments)
        return text
    }

    /**
     Adds the specified number of hours to a date and returns the result.
     - Parameter date: The starting date
     - Parameter hours: Hours to add
     */
    public func addHours(date: Date, hours: Double) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["date"] = MCPToolArgumentEncoder.encode(date)
        arguments["hours"] = hours
        let text = try await proxy.callTool("addHours", arguments: arguments)
        return text
    }

    /**
     Performs a 30-second countdown with progress updates
     */
    public func countdown() async throws -> String {
        let text = try await proxy.callTool("countdown")
        return text
    }

    /**
     Divides the numerator by the denominator and returns the quotient
     - Parameter denominator: Number to divide by (defaults to 1.0)
     - Parameter numerator: Number to be divided
     */
    public func divide(denominator: Double = 1, numerator: Double) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["denominator"] = denominator
        arguments["numerator"] = numerator
        let text = try await proxy.callTool("divide", arguments: arguments)
        return text
    }

    /**
     Formats a date/time as String
     - Parameter date: The Date to format
     */
    public func formatDateAsString(date: Date) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["date"] = MCPToolArgumentEncoder.encode(date)
        let text = try await proxy.callTool("formatDateAsString", arguments: arguments)
        return text
    }

    /**
     Gets the current date/time on the server
     */
    public func getCurrentDateTime() async throws -> String {
        let text = try await proxy.callTool("getCurrentDateTime")
        return text
    }

    /**
     Shows a greeting message
     - Parameter name: Name of the person to greet
     */
    public func greet(name: String) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["name"] = name
        let text = try await proxy.callTool("greet", arguments: arguments)
        return text
    }

    /**
     Multiplies two integers and returns their product
     - Parameter a: First factor
     - Parameter b: Second factor
     */
    public func multiply(a: Double, b: Double) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["a"] = a
        arguments["b"] = b
        let text = try await proxy.callTool("multiply", arguments: arguments)
        return text
    }

    /**
     A function to test doing nothing, not returning anything
     */
    public func noop() async throws -> String {
        let text = try await proxy.callTool("noop")
        return text
    }

    /**
     Returns the normalized URL by removing fragments and resolving the path.
     - Parameter url: The URL to normalize
     */
    public func normalizeURL(url: URL) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["url"] = MCPToolArgumentEncoder.encode(url)
        let text = try await proxy.callTool("normalizeURL", arguments: arguments)
        return text
    }

    /**
     A simple ping function that returns 'pong'
     */
    public func ping() async throws -> String {
        let text = try await proxy.callTool("ping")
        return text
    }

    /**
     A function returning a random file
     */
    public func randomFile() async throws -> String {
        let text = try await proxy.callTool("randomFile")
        return text
    }

    /**
     Requests contact information from the user
     */
    public func requestContactInfo() async throws -> String {
        let text = try await proxy.callTool("requestContactInfo")
        return text
    }

    /**
     Requests project preferences from the user
     */
    public func requestProjectPreferences() async throws -> String {
        let text = try await proxy.callTool("requestProjectPreferences")
        return text
    }

    /**
     Requests user credentials with validation
     */
    public func requestUserCredentials() async throws -> String {
        let text = try await proxy.callTool("requestUserCredentials")
        return text
    }

    /**
     Requests user preferences with enum options
     */
    public func requestUserPreferences() async throws -> String {
        let text = try await proxy.callTool("requestUserPreferences")
        return text
    }

    /**
     Returns the same data after logging its size, demonstrating byte-string encoding.
     - Parameter data: The data to round-trip
     */
    public func roundTripData(data: Data) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["data"] = MCPToolArgumentEncoder.encode(data)
        let text = try await proxy.callTool("roundTripData", arguments: arguments)
        return text
    }

    /**
     Returns the same UUID after logging it, demonstrating UUID round-tripping.
     - Parameter uuid: The UUID to round-trip
     */
    public func roundTripUUID(uuid: UUID) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["uuid"] = MCPToolArgumentEncoder.encode(uuid)
        let text = try await proxy.callTool("roundTripUUID", arguments: arguments)
        return text
    }

    /**
     Requests sampling from the client LLM
     - Parameter modelPreferences: Represents model preferences for sampling requests.
     - Parameter prompt: The prompt to send to the client's LLM
     */
    public func sampleFromClient(modelPreferences: [String: any Sendable]? = nil, prompt: String) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        if let modelPreferences { arguments["modelPreferences"] = modelPreferences }
        arguments["prompt"] = prompt
        let text = try await proxy.callTool("sampleFromClient", arguments: arguments)
        return text
    }

    /**
     Subtracts the second integer from the first and returns the difference
     - Parameter a: Number to subtract from
     - Parameter b: Number to subtract
     */
    public func subtract(a: Double = 5, b: Double = 3) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["a"] = a
        arguments["b"] = b
        let text = try await proxy.callTool("subtract", arguments: arguments)
        return text
    }

    /**
     Custom description: Tests array processing
     - Parameter a: Array of integers to process
     */
    public func testArray(a: [Double] = [1, 2, 3]) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["a"] = a
        let text = try await proxy.callTool("testArray", arguments: arguments)
        return text
    }
}