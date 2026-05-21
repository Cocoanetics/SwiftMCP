import Foundation

/// Protocol for servers that provide prompts to clients
public protocol MCPPromptProviding {
    /// Metadata for all prompt functions.
    ///
    /// Not declared `nonisolated` so actor-backed conformers can satisfy this
    /// requirement with an actor-isolated property. Class hosts emitted by
    /// `@MCPServer` still expose it as `nonisolated`, so existing class-based
    /// call sites continue to read it synchronously.
    var mcpPromptMetadata: [MCPPromptMetadata] { get async }

    /// Calls a prompt by name with provided arguments
    func callPrompt(_ name: String, arguments: JSONDictionary) async throws -> [PromptMessage]
}

extension MCPPromptProviding {
    public var mcpPromptMetadata: [MCPPromptMetadata] {
        get async { [] }
    }

    public func callPrompt(_ name: String, arguments: JSONDictionary) async throws -> [PromptMessage] {
        throw MCPToolError.unknownTool(name: name)
    }
}
