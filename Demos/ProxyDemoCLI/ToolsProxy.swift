import Foundation
import SwiftMCP
public actor SwiftMCPDemoProxy {
    // MARK: - Declarations
    /// A resource content implementation for files in the file system
    public struct RandomFileResponseItem: Codable, Sendable {
        /// The binary content of the resource (if it's a binary resource)
        public let blob: Data?
        /// The MIME type of the resource
        public let mimeType: String?
        /// The text content of the resource (if it's a text resource)
        public let text: String?
        /// The URI of the resource
        public let uri: URL?
    }

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
     - Returns: The sum of a and b
     */
    public func add(a: Double, b: Double) async throws -> Double {
        var arguments: [String: any Sendable] = [:]
        arguments["a"] = a
        arguments["b"] = b
        let text = try await proxy.callTool("add", arguments: arguments)
        return try MCPClientResultDecoder.decode(Double.self, from: text)
    }

    /**
     Performs a 30-second countdown with progress updates
     - Returns: A completion message
     */
    public func countdown() async throws -> String {
        let text = try await proxy.callTool("countdown")
        return text
    }

    /**
     Divides the numerator by the denominator and returns the quotient
     - Parameter denominator: Number to divide by (defaults to 1.0)
     - Parameter numerator: Number to be divided
     - Returns: The quotient of numerator divided by denominator
     */
    public func divide(denominator: Double? = nil, numerator: Double) async throws -> Double {
        var arguments: [String: any Sendable] = [:]
        if let denominator { arguments["denominator"] = denominator }
        arguments["numerator"] = numerator
        let text = try await proxy.callTool("divide", arguments: arguments)
        return try MCPClientResultDecoder.decode(Double.self, from: text)
    }

    /**
     Formats a date/time as String
     - Parameter date: The Date to format
     - Returns: A string with the date formatted
     */
    public func formatDateAsString(date: Date) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["date"] = MCPToolArgumentEncoder.encode(date)
        let text = try await proxy.callTool("formatDateAsString", arguments: arguments)
        return text
    }

    /**
     Gets the current date/time on the server
     - Returns: The current time
     */
    public func getCurrentDateTime() async throws -> Date {
        let text = try await proxy.callTool("getCurrentDateTime")
        return try MCPClientResultDecoder.decode(Date.self, from: text)
    }

    /**
     Shows a greeting message
     - Parameter name: Name of the person to greet
     - Returns: The greeting message
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
     - Returns: The product of a and b
     */
    public func multiply(a: Double, b: Double) async throws -> Double {
        var arguments: [String: any Sendable] = [:]
        arguments["a"] = a
        arguments["b"] = b
        let text = try await proxy.callTool("multiply", arguments: arguments)
        return try MCPClientResultDecoder.decode(Double.self, from: text)
    }

    /**
     A function to test doing nothing, not returning anything
     - Returns: A void function that performs an action
     */
    public func noop() async throws -> String {
        let text = try await proxy.callTool("noop")
        return text
    }

    /**
     A simple ping function that returns 'pong'
     - Returns: A structured response
     */
    public func ping() async throws -> String {
        let text = try await proxy.callTool("ping")
        return text
    }

    /**
     A function returning a random file
     - Returns: A multiple simple text files
     */
    public func randomFile() async throws -> [RandomFileResponseItem] {
        let text = try await proxy.callTool("randomFile")
        return try MCPClientResultDecoder.decode([RandomFileResponseItem].self, from: text)
    }

    /**
     Requests contact information from the user
     - Returns: A string describing the user's response or the action they took
     */
    public func requestContactInfo() async throws -> String {
        let text = try await proxy.callTool("requestContactInfo")
        return text
    }

    /**
     Requests project preferences from the user
     - Returns: A string describing the user's project preferences or their action
     */
    public func requestProjectPreferences() async throws -> String {
        let text = try await proxy.callTool("requestProjectPreferences")
        return text
    }

    /**
     Requests user credentials with validation
     - Returns: A string describing the user's response or the action they took
     */
    public func requestUserCredentials() async throws -> String {
        let text = try await proxy.callTool("requestUserCredentials")
        return text
    }

    /**
     Requests user preferences with enum options
     - Returns: A string describing the user's response or the action they took
     */
    public func requestUserPreferences() async throws -> String {
        let text = try await proxy.callTool("requestUserPreferences")
        return text
    }

    /**
     Requests sampling from the client LLM
     - Parameter modelPreferences: Represents model preferences for sampling requests.
     - Parameter prompt: The prompt to send to the client's LLM
     - Returns: The generated text from the client, or nil if no context is available
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
     - Returns: The difference between a and b
     */
    public func subtract(a: Double? = nil, b: Double? = nil) async throws -> Double {
        var arguments: [String: any Sendable] = [:]
        if let a { arguments["a"] = a }
        if let b { arguments["b"] = b }
        let text = try await proxy.callTool("subtract", arguments: arguments)
        return try MCPClientResultDecoder.decode(Double.self, from: text)
    }

    /**
     Custom description: Tests array processing
     - Parameter a: Array of integers to process
     - Returns: A string representation of the array
     */
    public func testArray(a: [Double]? = nil) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        if let a { arguments["a"] = a }
        let text = try await proxy.callTool("testArray", arguments: arguments)
        return text
    }
}