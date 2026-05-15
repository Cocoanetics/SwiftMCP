import Foundation
import Testing
@testable import SwiftMCP

// MARK: - Basic Type Array Tests

@Test("Tests processing of integer arrays")
func testIntArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processIntArray",
            "arguments": [
                "numbers": [1, 2, 3, 4, 5]
            ]
        ]
    )

    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == .int(1))
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[2,4,6,8,10]")
}

@Test("Tests processing of optional integer arrays")
func testOptionalIntArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalIntArray",
            "arguments": [:]
        ]
    )

    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == .int(1))
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[]")
}

@Test("Tests processing of string arrays")
func testStringArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processStringArray",
            "arguments": [
                "strings": ["hello", "world", "test"]
            ]
        ]
    )

    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == .int(1))
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[\"HELLO\",\"WORLD\",\"TEST\"]")
}

@Test("Tests processing of double arrays")
func testDoubleArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processDoubleArray",
            "arguments": [
                "numbers": [1.1, 2.2, 3.3]
            ]
        ]
    )

    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == .int(1))
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[2.2,4.4,6.6]")
}

@Test("Tests processing of optional double arrays")
func testOptionalDoubleArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalDoubleArray",
            "arguments": [
                "numbers": [1.1, 2.2, 3.3]
            ]
        ]
    )

    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == .int(1))
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[2.2,4.4,6.6]")
}

@Test("Tests processing of boolean arrays")
func testBooleanArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processBooleanArray",
            "arguments": [
                "values": [true, false, true]
            ]
        ]
    )

    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == .int(1))
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[false,true,false]")
}

@Test("Tests processing of optional boolean arrays")
func testOptionalBooleanArrayProcessing() async throws {
    let server = ComplexTypesServer()
    let client = MockClient(server: server)

    let request = JSONRPCMessage.request(
        id: 1,
        method: "tools/call",
        params: [
            "name": "processOptionalBooleanArray",
            "arguments": [
                "values": [true, false, true]
            ]
        ]
    )

    let message = await client.send(request)
    guard case .response(let response) = message else {
        #expect(Bool(false), "Expected response case")
        return
    }
    #expect(response.id == .int(1))
    let result = try #require(response.result)
    let isError = try #require(result["isError"]?.value as? Bool)
    #expect(isError == false)
    let content = try #require(result["content"]?.value as? [[String: String]])
    let firstContent = try #require(content.first)
    let type = try #require(firstContent["type"])
    let text = try #require(firstContent["text"])
    #expect(type == "text")
    #expect(text == "[false,true,false]")
}
