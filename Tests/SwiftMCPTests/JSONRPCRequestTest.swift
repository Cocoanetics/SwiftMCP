import Foundation
import Testing
@testable import SwiftMCP
import AnyCodable

@Test
func testDecodeJSONRPCRequest() throws {
	let jsonString = """
	{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":true,"prompts":false,"resources":true,"logging":false,"roots":{"listChanged":false}},"clientInfo":{"name":"cursor-vscode","version":"1.0.0"}},"jsonrpc":"2.0","id":0}
	"""
	
	let jsonData = jsonString.data(using: .utf8)!
	
	let request = try JSONDecoder().decode(JSONRPCMessage.self, from: jsonData)
	#expect(request.jsonrpc == "2.0")
	#expect(request.id == 0)
	#expect(request.method == "initialize")
	#expect(request.params != nil)
	#expect(request.result == nil)
	
	// Access the params dictionary directly
	guard let params = request.params else {
		throw TestError("params is nil")
	}
	
	// Check protocolVersion
	#expect(params["protocolVersion"]?.value as? String == "2024-11-05")
	
	// Check capabilities
	guard let capabilities = params["capabilities"]?.value as? [String: Any] else {
		throw TestError("capabilities not found or not a dictionary")
	}
	
	#expect(capabilities["tools"] as? Bool == true)
	#expect(capabilities["prompts"] as? Bool == false)
	#expect(capabilities["resources"] as? Bool == true)
	#expect(capabilities["logging"] as? Bool == false)
	
	// Check roots
	guard let roots = (capabilities["roots"] as? [String: Any]) else {
		throw TestError("roots not found or not a dictionary")
	}
	
	#expect(roots["listChanged"] as? Bool == false)
	
	// Check clientInfo
	guard let clientInfo = params["clientInfo"]?.value as? [String: Any] else {
		throw TestError("clientInfo not found or not a dictionary")
	}
	
	#expect(clientInfo["name"] as? String == "cursor-vscode")
	#expect(clientInfo["version"] as? String == "1.0.0")
}

@Test
func testDecodeJSONRPCResponse() throws {
	let jsonString = """
	{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"2024-11-05","capabilities":{"experimental":{},"resources":{"listChanged":false},"tools":{"listChanged":false}},"serverInfo":{"name":"TestServer","version":"1.0"}}}
	"""
	
	let jsonData = jsonString.data(using: .utf8)!
	
	let response = try JSONDecoder().decode(JSONRPCMessage.self, from: jsonData)
	#expect(response.jsonrpc == "2.0")
	#expect(response.id == 1)
	#expect(response.method == nil)
	#expect(response.params == nil)
	#expect(response.result != nil)
	#expect(response.error == nil)
	
	guard let result = response.result else {
		throw TestError("result is nil")
	}
	
	// Check protocolVersion
	#expect(result["protocolVersion"]?.value as? String == "2024-11-05")
	
	// Check capabilities
	guard let capabilities = result["capabilities"]?.value as? [String: Any] else {
		throw TestError("capabilities not found or not a dictionary")
	}
	
	// Check experimental is empty dictionary
	guard let experimental = capabilities["experimental"] as? [String: Any] else {
		throw TestError("experimental not found or not a dictionary")
	}
	#expect(experimental.isEmpty)
	
	guard let resources = capabilities["resources"] as? [String: Bool] else {
		throw TestError("resources not found or not a dictionary")
	}
	#expect(resources["listChanged"] == false)
	
	guard let tools = capabilities["tools"] as? [String: Bool] else {
		throw TestError("tools not found or not a dictionary")
	}
	#expect(tools["listChanged"] == false)
	
	// Check serverInfo
	guard let serverInfo = result["serverInfo"]?.value as? [String: String] else {
		throw TestError("serverInfo not found or not a dictionary")
	}
	
	#expect(serverInfo["name"] == "TestServer")
	#expect(serverInfo["version"] == "1.0")
}

@Test
func testDecodeJSONRPCError() throws {
	let jsonString = """
	{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"An error occurred"}}
	"""
	
	let jsonData = jsonString.data(using: .utf8)!
	
	let response = try JSONDecoder().decode(JSONRPCMessage.self, from: jsonData)
	#expect(response.jsonrpc == "2.0")
	#expect(response.id == 1)
	#expect(response.method == nil)
	#expect(response.params == nil)
	#expect(response.result == nil)
	#expect(response.error != nil)
	
	guard let error = response.error else {
		throw TestError("error is nil")
	}
	
	#expect(error.code == -32000)
	#expect(error.message == "An error occurred")
}
