import Foundation
import SwiftMCP

// MARK: - Response Models

/// Response for the initialize method
struct InitializeResponse: Codable {
    struct ServerInfo: Codable {
        let name: String
        let version: String
    }

    struct Capabilities: Codable {
        let experimental: [String: String]
        let tools: Tools
    }

    struct Tools: Codable {
        let listChanged: Bool
    }

    let jsonrpc: String
    let id: Int
    let result: Result

    struct Result: Codable {
        let protocolVersion: String
        let capabilities: Capabilities
        let serverInfo: ServerInfo
    }
    
    /// Creates a default initialize response
    static func createDefault(id: Int) -> InitializeResponse {
        return InitializeResponse(
            jsonrpc: "2.0",
            id: id,
            result: .init(
                protocolVersion: "2024-11-05",
                capabilities: .init(
                    experimental: [:],
                    tools: .init(listChanged: false)
                ),
                serverInfo: .init(name: "mcp-calculator", version: "1.0.0")
            )
        )
    }
}

/// Response for the tools/list method
struct ToolsListResponse: Codable {
    let jsonrpc: String
    let id: Int
    let result: Result

    struct Result: Codable {
        let tools: [MCPTool]
    }

    struct InputSchema: Codable {
        let type: String
        let properties: [String: Property]
        let required: [String]
    }

    struct Property: Codable {
        let type: String
        let description: String
    }
}

/// Response for the tools/call method
struct ToolCallResponse: Codable {
    let jsonrpc: String
    let id: Int
    let result: Result
    
    struct Result: Codable {
        let content: [ContentItem]
        let isError: Bool
        
        struct ContentItem: Codable {
            let type: String
            let text: String
        }
    }
    
    init(id: Int, text: String, isError: Bool = false) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = Result(
            content: [Result.ContentItem(type: "text", text: text)],
            isError: isError
        )
    }
} 