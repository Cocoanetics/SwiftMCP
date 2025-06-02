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
