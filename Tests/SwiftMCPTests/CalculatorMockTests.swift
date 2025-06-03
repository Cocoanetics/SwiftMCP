import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Test("Tests add function with mock client")
func testAddViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "add",
            "arguments": ["a": 2, "b": 3]
        ]
    )
    
    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    #expect(type == "text")
    #expect(text == "5")
}

@Test("Tests greet function with mock client")
func testGreetViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "greet",
            "arguments": ["name": "Oliver"]
        ]
    )
    
    guard let message = await client.send(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
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
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "subtract",
            "arguments": ["a": 10, "b": 4]
        ]
    )
    
    guard let message = await client.send(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    #expect(type == "text")
    #expect(text == "6")
}

@Test("Tests multiply function with mock client")
func testMultiplyViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "multiply",
            "arguments": ["a": 6, "b": 7]
        ]
    )
    
    guard let message = await client.send(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    #expect(type == "text")
    #expect(text == "42")
}

@Test("Tests divide function with mock client")
func testDivideViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "divide",
            "arguments": ["numerator": 10, "denominator": 2]
        ]
    )
    
    guard let message = await client.send(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    #expect(type == "text")
    #expect(text == "5")
}

@Test("Tests testArray function with mock client")
func testTestArrayViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "testArray",
            "arguments": ["a": [1, 2, 3, 4, 5]]
        ]
    )
    
    guard let message = await client.send(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
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
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "ping",
            "arguments": []
        ]
    )
    
    guard let message = await client.send(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
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
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "noop",
            "arguments": []
        ]
    )
    
    guard let message = await client.send(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    #expect(type == "text")
    #expect(text == "")
}

@Test("Tests getCurrentDateTime function with mock client")
func testGetCurrentDateTimeViaMockClient() async throws {
    let calculator = Calculator()
    let client = MockClient(server: calculator)
    
    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "getCurrentDateTime",
            "arguments": []
        ]
    )
    
    guard let message = await client.send(request) else {
        #expect(Bool(false), "Expected a response message")
        return
    }
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == 1)
    let result = unwrap(response.result)
    let isError = unwrap(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = unwrap(result["content"]?.value as? [[String: String]])
    let firstContent = unwrap(content.first)
    let type = unwrap(firstContent["type"])
    let text = unwrap(firstContent["text"])
    #expect(type == "text")
    // Verify the text is a valid ISO 8601 date string
    let dateFormatter = ISO8601DateFormatter()
    let date = dateFormatter.date(from: text.replacingOccurrences(of: "\"", with: ""))
    #expect(date != nil, "Response should be a valid ISO 8601 date string")
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
