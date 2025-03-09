import XCTest
import AnyCodable
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
			XCTAssertEqual(request.jsonrpc, "2.0")
			XCTAssertEqual(request.id, 0)
			XCTAssertEqual(request.method, "initialize")
			XCTAssertNotNil(request.params)
			
			// Access the params dictionary directly
			guard let params = request.params else {
				XCTFail("params is nil")
				return
			}
			
			// Check protocolVersion
			XCTAssertEqual(params["protocolVersion"]?.value as? String, "2024-11-05")
			
			// Check capabilities
			guard let capabilities = params["capabilities"]?.value as? [String: Any] else {
				XCTFail("capabilities not found or not a dictionary")
				return
			}
			
			XCTAssertEqual(capabilities["tools"] as? Bool, true)
			XCTAssertEqual(capabilities["prompts"] as? Bool, false)
			XCTAssertEqual(capabilities["resources"] as? Bool, true)
			XCTAssertEqual(capabilities["logging"] as? Bool, false)
			
			// Check roots
			guard let roots = (capabilities["roots"] as? [String: Any]) else {
				XCTFail("roots not found or not a dictionary")
				return
			}
			
			XCTAssertEqual(roots["listChanged"] as? Bool, false)
			
			// Check clientInfo
			guard let clientInfo = params["clientInfo"]?.value as? [String: Any] else {
				XCTFail("clientInfo not found or not a dictionary")
				return
			}
			
			XCTAssertEqual(clientInfo["name"] as? String, "cursor-vscode")
			XCTAssertEqual(clientInfo["version"] as? String, "1.0.0")
		} catch {
			XCTFail("Decoding failed with error: \(error)")
		}
	}
}
