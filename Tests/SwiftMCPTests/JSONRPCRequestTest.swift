import Foundation
import Testing
import AnyCodable
@testable import SwiftMCP

@Test
func testDecodeJSONRPCRequest() throws {
	let jsonString = """
	{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":true,"prompts":false,"resources":true,"logging":false,"roots":{"listChanged":false}},"clientInfo":{"name":"cursor-vscode","version":"1.0.0"}},"jsonrpc":"2.0","id":0}
	"""
	
	let jsonData = jsonString.data(using: .utf8)!
	
	let request = try JSONDecoder().decode(JSONRPCRequest.self, from: jsonData)
	#expect(request.jsonrpc == "2.0")
	#expect(request.id == 0)
	#expect(request.method == "initialize")
	#expect(request.params != nil)
	
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
