import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Test
func testDecodeJSONRPCRequest() throws {
	let json = """
	{"jsonrpc":"2.0","id":1,"method":"testMethod","params":{"foo":42}}
	""".data(using: .utf8)!
	let message = try JSONDecoder().decode(JSONRPCMessage.self, from: json)
	guard case .request(let request) = message else {
		throw TestError("Expected request case")
	}
	#expect(request.jsonrpc == "2.0")
	#expect(request.id == 1)
	#expect(request.method == "testMethod")
	#expect(request.params?["foo"]?.value as? Int == 42)
}

@Test
func testDecodeJSONRPCResponse() throws {
	let json = """
	{"jsonrpc":"2.0","id":1,"result":{"bar":"baz"}}
	""".data(using: .utf8)!
	let message = try JSONDecoder().decode(JSONRPCMessage.self, from: json)
	guard case .response(let response) = message else {
		throw TestError("Expected response case")
	}
	#expect(response.jsonrpc == "2.0")
	#expect(response.id == 1)
	#expect(response.result?["bar"]?.value as? String == "baz")
}

@Test
func testDecodeJSONRPCErrorResponse() throws {
	let json = """
	{"jsonrpc":"2.0","id":1,"error":{"code":-32601,"message":"Method not found"}}
	""".data(using: .utf8)!
	let message = try JSONDecoder().decode(JSONRPCMessage.self, from: json)
	guard case .errorResponse(let error) = message else {
		throw TestError("Expected errorResponse case")
	}
	#expect(error.jsonrpc == "2.0")
	#expect(error.id == 1)
	#expect(error.error.code == -32601)
	#expect(error.error.message == "Method not found")
}

@Test
func testDecodeJSONRPCBatch() throws {
	let json = """
	[
		{"jsonrpc":"2.0","id":1,"method":"ping"},
		{"jsonrpc":"2.0","method":"notifications/initialized"},
		{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
	]
	""".data(using: .utf8)!
	
	let batch = try JSONDecoder().decode([JSONRPCMessage].self, from: json)
	#expect(batch.count == 3)
	
	// Check first message is a request
	guard case .request(let request1) = batch[0] else {
		throw TestError("Expected first message to be request")
	}
	#expect(request1.id == 1)
	#expect(request1.method == "ping")
	
	// Check second message is a notification
	guard case .notification(let notification) = batch[1] else {
		throw TestError("Expected second message to be notification")
	}
	#expect(notification.method == "notifications/initialized")
	
	// Check third message is a request
	guard case .request(let request2) = batch[2] else {
		throw TestError("Expected third message to be request")
	}
	#expect(request2.id == 2)
	#expect(request2.method == "tools/list")
}

@Test
func testHandleBatchRequest() async throws {
	let calculator = Calculator()
	
	// Create a batch with mixed requests and notifications
	let batch: [JSONRPCMessage] = [
		.request(id: 1, method: "ping"),
		.notification(method: "notifications/initialized"),
		.request(id: 2, method: "tools/list")
	]
	
	var responses: [JSONRPCMessage] = []
	
	// Process each message in the batch
	for message in batch {
		if let response = await calculator.handleMessage(message) {
			responses.append(response)
		}
	}
	
	// Should have 2 responses (ping and tools/list), notification has no response
	#expect(responses.count == 2)
	
	// Check first response (ping)
	guard case .response(let response1) = responses[0] else {
		throw TestError("Expected first response to be response")
	}
	#expect(response1.id == 1)
	
	// Check second response (tools/list)
	guard case .response(let response2) = responses[1] else {
		throw TestError("Expected second response to be response")
	}
	#expect(response2.id == 2)
}

@Test
func testEncodeBatchResponse() throws {
	let responses: [JSONRPCMessage] = [
		.response(id: 1, result: [:]),
		.response(id: 2, result: ["tools": AnyCodable([])])
	]
	
	let encoder = JSONEncoder()
	let data = try encoder.encode(responses)
	
	// Verify it's a valid JSON array
	let decoded = try JSONDecoder().decode([JSONRPCMessage].self, from: data)
	#expect(decoded.count == 2)
	
	// Check first response
	guard case .response(let response1) = decoded[0] else {
		throw TestError("Expected first message to be response")
	}
	#expect(response1.id == 1)
	
	// Check second response
	guard case .response(let response2) = decoded[1] else {
		throw TestError("Expected second message to be response")
	}
	#expect(response2.id == 2)
}
