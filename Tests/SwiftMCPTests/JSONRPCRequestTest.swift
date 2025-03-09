import XCTest
@testable import SwiftMCP

final class JSONRPCTests: XCTestCase {
	
	// Test function to decode JSON-RPC request
	func testDecodeJSONRPCRequest() {
		let jsonString = """
	{"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{"tools":true,"prompts":false,"resources":true,"logging":false,"roots":{"listChanged":false}},"clientInfo":{"name":"cursor-vscode","version":"1.0.0"}},"jsonrpc":"2.0","id":0}
	"""
		
		let jsonData = jsonString.data(using: .utf8)!
		do {
			let request = try JSONDecoder().decode(JSONRPCRequest.self, from: jsonData)
			assert(request.jsonrpc == "2.0")
			assert(request.id == 0)
			assert(request.method == "initialize")
			assert(request.params != nil)
			
			if let protocolVersion = request.params?["protocolVersion"]?.value as? String {
				assert(protocolVersion == "2024-11-05")
			} else {
				print("protocolVersion not found or not a String")
			}
			
			if let capabilities = request.params?["capabilities"]?.value as? [String: AnyCodable] {
				assert(capabilities["tools"]?.value as? Bool == true)
				assert(capabilities["prompts"]?.value as? Bool == false)
				assert(capabilities["resources"]?.value as? Bool == true)
				assert(capabilities["logging"]?.value as? Bool == false)
				if let roots = capabilities["roots"]?.value as? [String: AnyCodable] {
					assert(roots["listChanged"]?.value as? Bool == false)
				} else {
					print("roots not found or not a dictionary")
				}
			} else {
				print("capabilities not found or not a dictionary")
			}
			
			if let clientInfo = request.params?["clientInfo"]?.value as? [String: AnyCodable] {
				assert(clientInfo["name"]?.value as? String == "cursor-vscode")
				assert(clientInfo["version"]?.value as? String == "1.0.0")
			} else {
				print("clientInfo not found or not a dictionary")
			}
		} catch {
			print("Decoding failed with error: \(error)")
		}
	}
}
