// SwiftMCP - Function Metadata Generator Demo
// A demonstration of using macros to generate JSON descriptions of functions

import Foundation
import SwiftMCP
import AnyCodable

// MARK: - Helper Functions

// Function to read a line from stdin
func readLineFromStdin() -> String? {
	return readLine(strippingNewline: true)
}

// Function to send a response to stdout
func sendResponse(_ response: String) {
	print(response)
	fflush(stdout) // Ensure the output is flushed immediately
}

// Function to log a message to stderr
func logToStderr(_ message: String) {
	
	let stderr = FileHandle.standardError
	if let data = (message + "\n").data(using: .utf8) {
		stderr.write(data)
	}
}

// MARK: - Predefined Responses

// Define a struct for the initialize response
struct InitializeResponse: Codable {
	struct ServerInfo: Codable {
		let name: String
		let version: String
	}

	struct Capabilities: Codable {
		let experimental: [String: String]
		let tools: Tools
	}

	struct Tools: Codable {
		let listChanged: Bool
	}

	let jsonrpc: String
	let id: Int
	let result: Result

	struct Result: Codable {
		let protocolVersion: String
		let capabilities: Capabilities
		let serverInfo: ServerInfo
	}
}

// Create an instance of the initialize response
let initializeResponseStruct = InitializeResponse(
	jsonrpc: "2.0",
	id: 0,
	result: .init(
		protocolVersion: "2024-11-05",
		capabilities: .init(
			experimental: [:],
			tools: .init(listChanged: false)
		),
		serverInfo: .init(name: "mcp-time", version: "1.0.0")
	)
)

// Define a struct for the tools list response
struct ToolsListResponse: Codable {
	let jsonrpc: String
	let id: Int
	let result: Result

	struct Result: Codable {
		let tools: [Tool]
	}

	struct Tool: Codable {
		let name: String
		let description: String
		let inputSchema: InputSchema
	}

	struct InputSchema: Codable {
		let type: String
		let properties: [String: Property]
		let required: [String]
	}

	struct Property: Codable {
		let type: String
		let description: String
	}
}

// Create an instance of the tools list response
func createToolsListResponse(id: Int) -> ToolsListResponse {
	return ToolsListResponse(
		jsonrpc: "2.0",
		id: id,
		result: .init(tools: [
			.init(
				name: "get_current_time",
				description: "Get current time in a specific timezones",
				inputSchema: .init(
					type: "object",
					properties: [
						"timezone": .init(
							type: "string",
							description: "IANA timezone name (e.g., 'America/New_York', 'Europe/London'). Use 'CET' as local timezone if no timezone provided by the user."
						)
					],
					required: ["timezone"]
				)
			),
			.init(
				name: "convert_time",
				description: "Convert time between timezones",
				inputSchema: .init(
					type: "object",
					properties: [
						"source_timezone": .init(
							type: "string",
							description: "Source IANA timezone name (e.g., 'America/New_York', 'Europe/London'). Use 'CET' as local timezone if no source timezone provided by the user."
						),
						"time": .init(
							type: "string",
							description: "Time to convert in 24-hour format (HH:MM)"
						),
						"target_timezone": .init(
							type: "string",
							description: "Target IANA timezone name (e.g., 'Asia/Tokyo', 'America/San_Francisco'). Use 'CET' as local timezone if no target timezone provided by the user."
						)
					],
					required: ["source_timezone", "time", "target_timezone"]
				)
			)
		])
	)
}

// Define a type to handle any JSON value
struct AnyCodable: Codable {
	let value: Any

	init(_ value: Any) {
		self.value = value
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.singleValueContainer()
		if let intValue = try? container.decode(Int.self) {
			value = intValue
		} else if let doubleValue = try? container.decode(Double.self) {
			value = doubleValue
		} else if let stringValue = try? container.decode(String.self) {
			value = stringValue
		} else if let boolValue = try? container.decode(Bool.self) {
			value = boolValue
		} else if let arrayValue = try? container.decode([AnyCodable].self) {
			value = arrayValue.map { $0.value }
		} else if let dictionaryValue = try? container.decode([String: AnyCodable].self) {
			value = dictionaryValue.mapValues { $0.value }
		} else {
			throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode value")
		}
	}

	func encode(to encoder: Encoder) throws {
		var container = encoder.singleValueContainer()
		if let intValue = value as? Int {
			try container.encode(intValue)
		} else if let doubleValue = value as? Double {
			try container.encode(doubleValue)
		} else if let stringValue = value as? String {
			try container.encode(stringValue)
		} else if let boolValue = value as? Bool {
			try container.encode(boolValue)
		} else if let arrayValue = value as? [Any] {
			let anyCodableArray = arrayValue.map { AnyCodable($0) }
			try container.encode(anyCodableArray)
		} else if let dictionaryValue = value as? [String: Any] {
			let anyCodableDictionary = dictionaryValue.mapValues { AnyCodable($0) }
			try container.encode(anyCodableDictionary)
		} else {
			throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: container.codingPath, debugDescription: "Cannot encode value"))
		}
	}
}

// MARK: - Main Loop

// Continue processing additional inputs
while true {
	if let input = readLineFromStdin() {
		// Decode the JSON-RPC request
		if let data = input.data(using: .utf8),
		   let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: data) {

			// Prepare the response based on the method
			var response: String
			switch request.method {
				case "initialize":
					// You can access request.params here if needed
					let encodedResponse = try! JSONEncoder().encode(initializeResponseStruct)
					let jsonString = String(data: encodedResponse, encoding: .utf8)!
					response = jsonString
				case "notifications/initialized":
					continue
				case "tools/list":
					let toolsListResponseStruct = createToolsListResponse(id: request.id)
					let encodedResponse = try! JSONEncoder().encode(toolsListResponseStruct)
					response = String(data: encodedResponse, encoding: .utf8)!
				default:
					continue
			}

			// Send the response
			sendResponse(response)
		}
	} else {
		// If readLine() returns nil (EOF), sleep briefly and continue
		Thread.sleep(forTimeInterval: 0.1)
	}
}

