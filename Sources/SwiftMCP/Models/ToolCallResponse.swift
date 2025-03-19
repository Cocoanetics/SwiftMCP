import Foundation

/// Response structure for tool calls
public struct ToolCallResponse: Codable {
    public var jsonrpc: String = "2.0"
    public let id: Int
    public let result: Result
    
    public struct Result: Codable {
        public let content: [ContentItem]
        public let isError: Bool
        
        public struct ContentItem: Codable {
            public let type: String
            public let text: String
            
            public init(type: String, text: String) {
                self.type = type
                self.text = text
            }
        }
        
        public init(content: [ContentItem], isError: Bool) {
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
