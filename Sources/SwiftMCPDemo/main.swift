// SwiftMCP - Function Metadata Generator Demo
// A demonstration of using macros to generate JSON descriptions of functions

import Foundation
import SwiftMCP
import AnyCodable

// Create an instance of the Calculator
let calculator = Calculator()

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

// MARK: - JSONRPCRequest Extensions

// No need for extensions since we've moved the helper methods to the JSONRPCRequest struct

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
		serverInfo: .init(name: "mcp-calculator", version: "1.0.0")
	)
)

// Define a struct for the tools list response
struct ToolsListResponse: Codable {
	let jsonrpc: String
	let id: Int
	let result: Result

	struct Result: Codable {
		let tools: [MCPTool]
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

// Define a struct for the tool call response
struct ToolCallResponse: Codable {
    let jsonrpc: String
    let id: Int
    let result: Result
    
    struct Result: Codable {
        let content: [ContentItem]
        let isError: Bool
        
        struct ContentItem: Codable {
            let type: String
            let text: String
        }
    }
    
    init(id: Int, text: String, isError: Bool = false) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = Result(
            content: [Result.ContentItem(type: "text", text: text)],
            isError: isError
        )
    }
}

// Create an instance of the tools list response using the mcpTools from Calculator
func createToolsListResponse(id: Int) -> ToolsListResponse {
	// Convert MCPTool array to ToolsListResponse.Tool array
	let tools = calculator.mcpTools
	
	// Create and return the response
	return ToolsListResponse(
		jsonrpc: "2.0",
		id: id,
		result: .init(tools: tools)
	)
}

// MARK: - Main Loop

// Continue processing additional inputs
while true {
	if let input = readLineFromStdin(), let data = input.data(using: .utf8) {
		// Log the input for debugging
		logToStderr("Received input: \(input)")

		do {
			// Try to decode the JSON-RPC request
			let request = try JSONDecoder().decode(JSONRPCRequest.self, from: data)
			
			// Prepare the response based on the method
			var response: String
			switch request.method {
				case "initialize":
					let encodedResponse = try! JSONEncoder().encode(initializeResponseStruct)
					let jsonString = String(data: encodedResponse, encoding: .utf8)!
					response = jsonString
					
					// Log the params for debugging
					if let params = request.params {
						logToStderr("Params: \(params)")
						
						// Access direct values
						if let protocolVersion = request.getParamValue(key: "protocolVersion") {
							logToStderr("Protocol Version: \(protocolVersion)")
						}
						
						// Access nested values using path
						if let tools = request.getNestedParamValue(path: ["capabilities", "tools"]) as? Bool {
							logToStderr("Tools: \(tools)")
						}
						
						if let clientName = request.getNestedParamValue(path: ["clientInfo", "name"]) as? String {
							logToStderr("Client Name: \(clientName)")
						}
					}
				case "notifications/initialized":
					continue
				case "tools/list":
					let toolsListResponseStruct = createToolsListResponse(id: request.id)
					let encodedResponse = try! JSONEncoder().encode(toolsListResponseStruct)
					response = String(data: encodedResponse, encoding: .utf8)!
				case "tools/call":
					// Handle tool call
					if let params = request.params,
					   let toolName = params["name"]?.value as? String {
						
						logToStderr("Tool call: \(toolName)")
						
						// Get the arguments and prepare response text
						var responseText = ""
						var isError = false
						
						// Extract arguments from the request
						let arguments = (params["arguments"]?.value as? [String: Any]) ?? [:]
						
						// Call the appropriate wrapper method based on the tool name
						var result: Any? = nil
						
						switch toolName {
						case "greet":
							result = calculator.__call_greet(arguments)
						case "add":
							result = calculator.__call_add(arguments)
						case "subtract":
							result = calculator.__call_subtract(arguments)
						case "multiply":
							result = calculator.__call_multiply(arguments)
						case "divide":
							result = calculator.__call_divide(arguments)
						case "testArray":
							result = calculator.__call_testArray(arguments)
						case "ping":
							result = calculator.__call_ping(arguments)
						default:
							responseText = "Error: Unknown tool '\(toolName)'"
							isError = true
						}
						
						// If we got a result, format it as a response
						if !isError {
							if let result = result {
								responseText = "\(result)"
							} else {
								responseText = "Error: Function call failed"
								isError = true
							}
						}
						
						// Create and encode the response
						let toolCallResponseStruct = ToolCallResponse(id: request.id, text: responseText, isError: isError)
						let encodedResponse = try! JSONEncoder().encode(toolCallResponseStruct)
						response = String(data: encodedResponse, encoding: .utf8)!
					} else {
						// Invalid tool call request
						logToStderr("Invalid tool call request: missing tool name or arguments")
						continue
					}
				default:
					continue
			}
			
			// Send the response
			sendResponse(response)
		} catch {
			logToStderr("Failed to decode JSON-RPC request: \(error)")
			
			// Fallback to the previous approach
			if let json = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
			   let method = json["method"] as? String,
			   let _ = json["jsonrpc"] as? String,
			   let id = json["id"] as? Int {
				
				// Prepare the response based on the method
				var response: String
				switch method {
					case "initialize":
						let encodedResponse = try! JSONEncoder().encode(initializeResponseStruct)
						let jsonString = String(data: encodedResponse, encoding: .utf8)!
						response = jsonString
					case "notifications/initialized":
						continue
					case "tools/list":
						let toolsListResponseStruct = createToolsListResponse(id: id)
						let encodedResponse = try! JSONEncoder().encode(toolsListResponseStruct)
						response = String(data: encodedResponse, encoding: .utf8)!
					case "tools/call":
						// Handle tool call in fallback mode
						if let params = json["params"] as? [String: Any],
						   let toolName = params["name"] as? String {
							
							logToStderr("Tool call (fallback): \(toolName)")
							
							// Get the arguments and prepare response text
							var responseText = ""
							var isError = false
							
							// Extract arguments from the request
							let arguments = (params["arguments"] as? [String: Any]) ?? [:]
							
							// Call the appropriate wrapper method based on the tool name
							var result: Any? = nil
							
							switch toolName {
							case "greet":
								result = calculator.__call_greet(arguments)
							case "add":
								result = calculator.__call_add(arguments)
							case "subtract":
								result = calculator.__call_subtract(arguments)
							case "multiply":
								result = calculator.__call_multiply(arguments)
							case "divide":
								result = calculator.__call_divide(arguments)
							case "testArray":
								result = calculator.__call_testArray(arguments)
							case "ping":
								result = calculator.__call_ping(arguments)
							default:
								responseText = "Error: Unknown tool '\(toolName)'"
								isError = true
							}
							
							// If we got a result, format it as a response
							if !isError {
								if let result = result {
									responseText = "\(result)"
								} else {
									responseText = "Error: Function call failed"
									isError = true
								}
							}
							
							// Create and encode the response
							let toolCallResponseStruct = ToolCallResponse(id: id, text: responseText, isError: isError)
							let encodedResponse = try! JSONEncoder().encode(toolCallResponseStruct)
							response = String(data: encodedResponse, encoding: .utf8)!
						} else {
							// Invalid tool call request
							logToStderr("Invalid tool call request (fallback): missing tool name or arguments")
							continue
						}
					default:
						continue
				}
				
				// Send the response
				sendResponse(response)
			} else {
				logToStderr("Failed to parse JSON-RPC request")
			}
		}
	} else {
		// If readLine() returns nil (EOF), sleep briefly and continue
		Thread.sleep(forTimeInterval: 0.1)
	}
}

