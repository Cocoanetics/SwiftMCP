// SwiftMCP - Function Metadata Generator Demo
// A demonstration of using macros to generate JSON descriptions of functions

import Foundation
import SwiftMCP

//// Run the MCP demo directly without requiring any command-line arguments
//MCPDemo.run()
//
//// The program will exit in the MCPDemo.run() method after sending the response 

import Foundation

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

// Define the responses
let initializeResponse = """
{"jsonrpc":"2.0","id":0,"result":{"protocolVersion":"2024-11-05","capabilities":{"experimental":{},"tools":{"listChanged":false}},"serverInfo":{"name":"mcp-time","version":"1.0.0"}}}
"""

let listToolsResponse = """
{"jsonrpc":"2.0","id":2,"result":{"tools":[{"name":"get_current_time","description":"Get current time in a specific timezones","inputSchema":{"type":"object","properties":{"timezone":{"type":"string","description":"IANA timezone name (e.g., 'America/New_York', 'Europe/London'). Use 'CET' as local timezone if no timezone provided by the user."}},"required":["timezone"]}},{"name":"convert_time","description":"Convert time between timezones","inputSchema":{"type":"object","properties":{"source_timezone":{"type":"string","description":"Source IANA timezone name (e.g., 'America/New_York', 'Europe/London'). Use 'CET' as local timezone if no source timezone provided by the user."},"time":{"type":"string","description":"Time to convert in 24-hour format (HH:MM)"},"target_timezone":{"type":"string","description":"Target IANA timezone name (e.g., 'Asia/Tokyo', 'America/San_Francisco'). Use 'CET' as local timezone if no target timezone provided by the user."}},"required":["source_timezone","time","target_timezone"]}}]}}
"""

// Main loop
if let firstInput = readLineFromStdin() {
	//sendResponse(initializeResponse)
	
	// Example Usage
	
	let response = JSONRPCResponse(id: 0, result: .init(protocolVersion: "2024-11-05", capabilities: .init(tools: .init(listChanged: false)), serverInfo: .init(name: "mcp-time", version: "0.0.1")))

	let encoder = JSONEncoder()
	encoder.outputFormatting = .withoutEscapingSlashes  // Ensures minimal escaping

	if let jsonData = try? encoder.encode(response),
	   let jsonString = String(data: jsonData, encoding: .utf8) {
		sendResponse(jsonString)  // ✅ Guaranteed "jsonrpc" first!
	}
}

if let secondInput = readLineFromStdin() {
	 // sendResponse(listToolsResponse)
}

while true
{
	if let thirdInput = readLineFromStdin() {
		sendResponse(listToolsResponse)
		
		logToStderr(thirdInput)
	}
}

