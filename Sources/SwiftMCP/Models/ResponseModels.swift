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
