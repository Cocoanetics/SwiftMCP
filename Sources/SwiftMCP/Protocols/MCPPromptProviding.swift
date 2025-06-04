import Foundation

/// Protocol for servers that provide prompts to clients
public protocol MCPPromptProviding {
    /// Metadata for all prompt functions
    nonisolated var mcpPromptMetadata: [MCPPromptMetadata] { get }

    /// Calls a prompt by name with provided arguments
    func callPrompt(_ name: String, arguments: [String: Sendable]) async throws -> [PromptMessage]
}

extension MCPPromptProviding {
    public var mcpPromptMetadata: [MCPPromptMetadata] { [] }

    public func callPrompt(_ name: String, arguments: [String: Sendable]) async throws -> [PromptMessage] {
        throw MCPToolError.unknownTool(name: name)
    }
}
