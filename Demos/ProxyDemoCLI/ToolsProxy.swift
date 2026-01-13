//
//  ToolsProxy.swift
//  Generated: 2026-01-06T00:03:05+01:00
//  Server: SwiftMCP Demo (1.0)
//  Source: sse http://mac-studio.local:8080/sse
//  OpenAPI: http://mac-studio.local:8080/openapi.json
//

import Foundation
import SwiftMCP

/**
 A Calculator for simple math doing additionals, subtractions etc.
 
 Testing "quoted" stuff. And on multiple lines. 'single quotes'
 
 Return types are enhanced using OpenAPI metadata.
*/
public actor SwiftMCPDemoProxy {
    // MARK: - Declarations
    /// A simple weather report response
    public struct GetWeatherReportResponse: Codable, Sendable {
        /// Weather conditions description
        public let conditions: String?
        /// Humidity percentage
        public let humidity: Double?
        /// Location for the report
        public let location: String?
        /// Temperature in celsius
        public let temperature: Double?
    }

    /// A small PNG file
    public struct RandomImageResponse: Codable, Sendable {
        /// Optional content annotations
        public let annotations: RandomImageResponseAnnotations?
        /// Base64-encoded image data
        public let data: Data?
        /// Image MIME type
        public let mimeType: String?
        public let type: RandomImageResponseType?
    }

    /// Optional content annotations
    public struct RandomImageResponseAnnotations: Codable, Sendable {
        /// Audience list
        public let audience: [String]?
        /// ISO 8601 timestamp
        public let lastModified: Date?
        /// Priority (0.0-1.0)
        public let priority: Double?
    }

    public enum RandomImageResponseType: String, Codable, Sendable, CaseIterable {
        case image = "image"
    }

    // MARK: - Metadata
    public static let serverName: String? = "SwiftMCP Demo"

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
     Adds the specified number of hours to a date and returns the result.
     - Parameter date: The starting date
     - Parameter hours: Hours to add
     - Returns: The adjusted date
     */
    public func addHours(date: Date, hours: Double) async throws -> Date {
        var arguments: [String: any Sendable] = [:]
        arguments["date"] = MCPToolArgumentEncoder.encode(date)
        arguments["hours"] = hours
        let text = try await proxy.callTool("addHours", arguments: arguments)
        return try MCPClientResultDecoder.decode(Date.self, from: text)
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
    public func divide(denominator: Double = 1, numerator: Double) async throws -> Double {
        var arguments: [String: any Sendable] = [:]
        arguments["denominator"] = denominator
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
     Returns a mock weather report for the supplied location.
     - Parameter location: City name or zip code
     - Returns: A weather report
     */
    public func getWeatherReport(location: String) async throws -> GetWeatherReportResponse {
        var arguments: [String: any Sendable] = [:]
        arguments["location"] = location
        let text = try await proxy.callTool("getWeatherReport", arguments: arguments)
        return try MCPClientResultDecoder.decode(GetWeatherReportResponse.self, from: text)
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
     Returns the normalized URL by removing fragments and resolving the path.
     - Parameter url: The URL to normalize
     - Returns: The normalized URL
     */
    public func normalizeURL(url: URL) async throws -> URL {
        var arguments: [String: any Sendable] = [:]
        arguments["url"] = MCPToolArgumentEncoder.encode(url)
        let text = try await proxy.callTool("normalizeURL", arguments: arguments)
        return try MCPClientResultDecoder.decode(URL.self, from: text)
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
     A function returning a random image
     - Returns: A small PNG file
     */
    public func randomImage() async throws -> RandomImageResponse {
        let text = try await proxy.callTool("randomImage")
        return try MCPClientResultDecoder.decode(RandomImageResponse.self, from: text)
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
     Returns the same data after logging its size, demonstrating byte-string encoding.
     - Parameter data: The data to round-trip
     - Returns: The same data
     */
    public func roundTripData(data: Data) async throws -> Data {
        var arguments: [String: any Sendable] = [:]
        arguments["data"] = MCPToolArgumentEncoder.encode(data)
        let text = try await proxy.callTool("roundTripData", arguments: arguments)
        return try MCPClientResultDecoder.decode(Data.self, from: text)
    }

    /**
     Returns the same UUID after logging it, demonstrating UUID round-tripping.
     - Parameter uuid: The UUID to round-trip
     - Returns: The same UUID
     */
    public func roundTripUUID(uuid: UUID) async throws -> UUID {
        var arguments: [String: any Sendable] = [:]
        arguments["uuid"] = MCPToolArgumentEncoder.encode(uuid)
        let text = try await proxy.callTool("roundTripUUID", arguments: arguments)
        return try MCPClientResultDecoder.decode(UUID.self, from: text)
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
    public func subtract(a: Double = 5, b: Double = 3) async throws -> Double {
        var arguments: [String: any Sendable] = [:]
        arguments["a"] = a
        arguments["b"] = b
        let text = try await proxy.callTool("subtract", arguments: arguments)
        return try MCPClientResultDecoder.decode(Double.self, from: text)
    }

    /**
     Custom description: Tests array processing
     - Parameter a: Array of integers to process
     - Returns: A string representation of the array
     */
    public func testArray(a: [Double] = [1, 2, 3]) async throws -> String {
        var arguments: [String: any Sendable] = [:]
        arguments["a"] = a
        let text = try await proxy.callTool("testArray", arguments: arguments)
        return text
    }
}
