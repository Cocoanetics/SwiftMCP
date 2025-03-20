import Foundation
import Testing
@testable import SwiftMCP
import NIOCore
import NIOHTTP1
import AnyCodable
import Logging

// Initialize logging once for all tests
fileprivate let _initializeLogging: Void = {
	LoggingSystem.bootstrap { _ in NoOpLogHandler() }
}()

fileprivate func createTransport() async throws -> (HTTPSSETransport, MCPClient) {
	// Ensure logging is initialized
	_ = _initializeLogging
	
	// Try up to 3 different ports
	for _ in 1...3 {
		// Create random port
		let port = Int.random(in: 49152...65535)
		
		// Create and configure transport
		let calculator = Calculator()
		let transport = HTTPSSETransport(server: calculator, port: port)
		transport.serveOpenAPI = true
		
		do {
			// Start transport
			try await transport.start()
			
			// Wait for server to be ready with exponential backoff
			for i in 0..<4 {
				let delay = UInt64(pow(2.0, Double(i))) * 250_000_000 // 250ms, 500ms, 1s, 2s
				try await Task.sleep(nanoseconds: delay)
				
				// Create client
				let endpointURL = URL(string: "http://localhost:\(port)")!
				let client = MCPClient(endpointURL: endpointURL.appendingPathComponent("sse"))
				
				do {
					try await client.connect()
					return (transport, client)
				} catch {
					// If this isn't our last retry, continue to next attempt
					if i < 3 { continue }
					// On last retry, throw the error
					try await transport.stop()
					throw error
				}
			}
			
			// If we get here, all retries failed
			try await transport.stop()
			continue
			
		} catch {
			// If transport start fails, try next port
			continue
		}
	}
	
	throw MCPError.notConnected
}

@Test("Calls the add function")
func testAddViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 1,
		method: "tools/call",
		params: [
			"name": "add",
			"arguments": [
				"a": 2,
				"b": 3
			]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 1)
	#expect(jsonResponse.error == nil)
	#expect(jsonResponse.method == nil)
	#expect(jsonResponse.params == nil)
	
	let result = unwrap(jsonResponse.result)
	
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "5")  // 2 + 3 = 5
	
	try await transport.stop()
}

@Test("Tests if the OpenAPI spec is being served")
func testOPENAPI() async throws {
	// Create transport without client for OpenAPI test
	let port = Int.random(in: 8000..<10000)
	let endpointURL = URL(string: "http://localhost:\(port)")!
	
	let calculator = Calculator()
	let transport = HTTPSSETransport(server: calculator, port: port)
	transport.serveOpenAPI = true
	
	try await transport.start()
	
	let openAPIURL = endpointURL.appending(component: "openapi.json")
	let (openAPIData, openAPIResponse) = try await URLSession.shared.data(from: openAPIURL)
	let openAPIHTTPResponse = unwrap(openAPIResponse as? HTTPURLResponse)
	#expect(openAPIHTTPResponse.statusCode == 200)
	
	let decoder = JSONDecoder()
	let openAPISpec = try decoder.decode(OpenAPISpec.self, from: openAPIData)
	
	#expect(openAPISpec.openapi.hasPrefix("3."))  // Should be OpenAPI 3.x
	#expect(openAPISpec.info.title == "Calculator")  // Default server name
	#expect(openAPISpec.paths.isEmpty == false)
	
	try await transport.stop()
}

@Test("Tests the greet function with valid input")
func testGreetViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 2,
		method: "tools/call",
		params: [
			"name": "greet",
			"arguments": [
				"name": "Oliver"
			]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 2)
	#expect(jsonResponse.error == nil)
	#expect(jsonResponse.method == nil)
	#expect(jsonResponse.params == nil)
	
	let result = unwrap(jsonResponse.result)
	
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "Hello, Oliver!")
	
	try await transport.stop()
}

@Test("Tests the greet function with invalid input (too short)")
func testGreetErrorViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 3,
		method: "tools/call",
		params: [
			"name": "greet",
			"arguments": [
				"name": "a"
			]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 3)
	#expect(jsonResponse.error == nil)
	#expect(jsonResponse.method == nil)
	#expect(jsonResponse.params == nil)
	
	let result = unwrap(jsonResponse.result)
	
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == true)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "Name 'a' is too short. Names must be at least 2 characters long.")
	
	try await transport.stop()
}

@Test("Tests the subtract function")
func testSubtractViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 4,
		method: "tools/call",
		params: [
			"name": "subtract",
			"arguments": [
				"a": 5,
				"b": 3
			]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 4)
	#expect(jsonResponse.error == nil)
	
	let result = unwrap(jsonResponse.result)
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "2")  // 5 - 3 = 2
	
	try await transport.stop()
}

@Test("Tests the multiply function")
func testMultiplyViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 5,
		method: "tools/call",
		params: [
			"name": "multiply",
			"arguments": [
				"a": 4,
				"b": 3
			]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 5)
	#expect(jsonResponse.error == nil)
	
	let result = unwrap(jsonResponse.result)
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "12")  // 4 * 3 = 12
	
	try await transport.stop()
}

@Test("Tests the divide function")
func testDivideViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 6,
		method: "tools/call",
		params: [
			"name": "divide",
			"arguments": [
				"numerator": 10,
				"denominator": 2
			]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 6)
	#expect(jsonResponse.error == nil)
	
	let result = unwrap(jsonResponse.result)
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "5.0")  // 10 / 2 = 5.0
	
	try await transport.stop()
}

@Test("Tests the divide function with default denominator")
func testDivideDefaultViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 7,
		method: "tools/call",
		params: [
			"name": "divide",
			"arguments": [
				"numerator": 10
			]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 7)
	#expect(jsonResponse.error == nil)
	
	let result = unwrap(jsonResponse.result)
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "10.0")  // 10 / 1 = 10.0 (default denominator is 1.0)
	
	try await transport.stop()
}

@Test("Tests the array processing function")
func testArrayViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 8,
		method: "tools/call",
		params: [
			"name": "testArray",
			"arguments": [
				"a": [1, 2, 3, 4, 5]
			]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 8)
	#expect(jsonResponse.error == nil)
	
	let result = unwrap(jsonResponse.result)
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "1, 2, 3, 4, 5")  // Array is returned as comma-separated values
	
	try await transport.stop()
}

@Test("Tests the ping function")
func testPingViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 9,
		method: "tools/call",
		params: [
			"name": "ping",
			"arguments": [:]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 9)
	#expect(jsonResponse.error == nil)
	
	let result = unwrap(jsonResponse.result)
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "pong")
	
	try await transport.stop()
}

@Test("Tests the noop function")
func testNoopViaClient() async throws {
	let (transport, client) = try await createTransport()
	
	let toolRequest = JSONRPCMessage(
		id: 10,
		method: "tools/call",
		params: [
			"name": "noop",
			"arguments": [:]
		]
	)
	
	let jsonResponse = try await client.send(toolRequest)
	
	#expect(jsonResponse.id == 10)
	#expect(jsonResponse.error == nil)
	
	let result = unwrap(jsonResponse.result)
	let isError = unwrap(result["isError"]?.value as? Bool)
	#expect(isError == false)
	
	let content = unwrap(result["content"]?.value as? [[String: String]])
	let firstContent = unwrap(content.first)
	let type = unwrap(firstContent["type"])
	let text = unwrap(firstContent["text"])
	
	#expect(type == "text")
	#expect(text == "")  // noop returns empty string
	
	try await transport.stop()
}
