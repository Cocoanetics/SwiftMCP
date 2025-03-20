import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

/// A mock client that directly calls the Calculator's handleRequest method
class MockClient {
    private let calculator: Calculator
    
    init(calculator: Calculator) {
        self.calculator = calculator
    }
    
    func send(_ request: JSONRPCMessage) async throws -> JSONRPCMessage {
        guard let response = await calculator.handleRequest(request) else {
            throw MCPError.invalidResponse
        }
        return response
    }
}

@Test("Tests add function with mock client")
func testAddViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(calculator: calculator)
    
    let request = JSONRPCMessage(
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
    
    let response = try await client.send(request)
    
    #expect(response.id == 1)
    #expect(response.error == nil)
    #expect(response.method == nil)
    #expect(response.params == nil)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "5")  // 2 + 3 = 5
}

@Test("Tests greet function with mock client")
func testGreetViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(calculator: calculator)
    
    let request = JSONRPCMessage(
        id: 2,
        method: "tools/call",
        params: [
            "name": "greet",
            "arguments": [
                "name": "Oliver"
            ]
        ]
    )
    
    let response = try await client.send(request)
    
    #expect(response.id == 2)
    #expect(response.error == nil)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "Hello, Oliver!")
}

@Test("Tests subtract function with mock client")
func testSubtractViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(calculator: calculator)
    
    let request = JSONRPCMessage(
        id: 3,
        method: "tools/call",
        params: [
            "name": "subtract",
            "arguments": [
                "a": 5,
                "b": 3
            ]
        ]
    )
    
    let response = try await client.send(request)
    
    #expect(response.id == 3)
    #expect(response.error == nil)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "2")  // 5 - 3 = 2
}

@Test("Tests multiply function with mock client")
func testMultiplyViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(calculator: calculator)
    
    let request = JSONRPCMessage(
        id: 4,
        method: "tools/call",
        params: [
            "name": "multiply",
            "arguments": [
                "a": 4,
                "b": 3
            ]
        ]
    )
    
    let response = try await client.send(request)
    
    #expect(response.id == 4)
    #expect(response.error == nil)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "12")  // 4 * 3 = 12
}

@Test("Tests divide function with mock client")
func testDivideViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(calculator: calculator)
    
    let request = JSONRPCMessage(
        id: 5,
        method: "tools/call",
        params: [
            "name": "divide",
            "arguments": [
                "numerator": 10,
                "denominator": 2
            ]
        ]
    )
    
    let response = try await client.send(request)
    
    #expect(response.id == 5)
    #expect(response.error == nil)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "5.0")  // 10 / 2 = 5.0
}

@Test("Tests array processing with mock client")
func testArrayViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(calculator: calculator)
    
    let request = JSONRPCMessage(
        id: 6,
        method: "tools/call",
        params: [
            "name": "testArray",
            "arguments": [
                "a": [1, 2, 3, 4, 5]
            ]
        ]
    )
    
    let response = try await client.send(request)
    
    #expect(response.id == 6)
    #expect(response.error == nil)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "1, 2, 3, 4, 5")
}

@Test("Tests ping function with mock client")
func testPingViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(calculator: calculator)
    
    let request = JSONRPCMessage(
        id: 7,
        method: "tools/call",
        params: [
            "name": "ping",
            "arguments": [:]
        ]
    )
    
    let response = try await client.send(request)
    
    #expect(response.id == 7)
    #expect(response.error == nil)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "pong")
}

@Test("Tests noop function with mock client")
func testNoopViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(calculator: calculator)
    
    let request = JSONRPCMessage(
        id: 8,
        method: "tools/call",
        params: [
            "name": "noop",
            "arguments": [:]
        ]
    )
    
    let response = try await client.send(request)
    
    #expect(response.id == 8)
    #expect(response.error == nil)
    
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    
    #expect(type == "text")
    #expect(text == "")  // noop returns empty string
} 

/// Errors that can occur during MCP client operations
public enum MCPError: LocalizedError {
	case notConnected
	case invalidEndpointURL
	case invalidResponse
	case timeout
	
	public var errorDescription: String? {
		switch self {
		case .notConnected:
			return "Client is not connected to the server"
		case .invalidEndpointURL:
			return "Invalid messages endpoint URL received from server"
		case .invalidResponse:
			return "Invalid response received from server"
		case .timeout:
			return "Request timed out"
		}
	}
}
