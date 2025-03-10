import Foundation
import AnyCodable

// MARK: - Response Models

/// Response structure for the tools/list method
public struct ToolsResponse: Codable {
    public let jsonrpc: String
    public let id: Int
    public let result: ToolsResult
    
    public init(jsonrpc: String = "2.0", id: Int, result: ToolsResult) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
    }
    
    public struct ToolsResult: Codable {
        public let tools: [MCPTool]
        
        public init(tools: [MCPTool]) {
            self.tools = tools
        }
    }
}

/// Response structure for tool calls
public struct ToolCallResponse: Codable {
    public let jsonrpc: String
    public let id: Int
    public let result: Result
    
    public init(id: Int, text: String, isError: Bool = false, jsonrpc: String = "2.0") {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = Result(
            status: isError ? "error" : "success",
            content: [Result.ContentItem(type: "text", text: text)]
        )
    }
    
    public struct Result: Codable {
        public let status: String
        public let content: [ContentItem]
        
        public struct ContentItem: Codable {
            public let type: String
            public let text: String
            
            public init(type: String, text: String) {
                self.type = type
                self.text = text
            }
        }
        
        public init(status: String, content: [ContentItem]) {
            self.status = status
            self.content = content
        }
    }
} 
