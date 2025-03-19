import Foundation

/// Response structure for tool calls
struct ToolCallResponse: Codable {
	var jsonrpc: String = "2.0"
	let id: Int
	let result: Result
	
	struct Result: Codable {
		let content: [ContentItem]
		let isError: Bool
		
		public struct ContentItem: Codable {
			let type: String
			let text: String
			
			init(type: String, text: String) {
				self.type = type
				self.text = text
			}
		}
		
		init(content: [ContentItem], isError: Bool) {
			self.content = content
			self.isError = isError
		}
	}
}

extension ToolCallResponse {
	init(id: Int, error: Error)
	{
		self.id = id
		self.result = Result(
			content: [Result.ContentItem(type: "text", text: error.localizedDescription)],
			isError: true
		)
	}
	
	init(id: Int, result: String)
	{
		self.id = id
		self.result = Result(
			content: [Result.ContentItem(type: "text", text: result)],
			isError: false
		)
	}
}
