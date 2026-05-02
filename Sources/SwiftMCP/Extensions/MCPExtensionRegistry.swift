//
//  MCPExtensionContribution.swift
//  SwiftMCP
//
//  Per-instance contribution from a `@MCPExtension(_)`-annotated extension.
//  Carries metadata + dispatchers for tools, resources, and prompts. Each
//  `@MCPServer` type stores a private array of these on every instance;
//  `MyServer.<Name>.register(in: server)` appends to it. No global state.
//

import Foundation

/// One block of MCP capabilities contributed by a `@MCPExtension`.
///
/// Each kind (tool, resource, prompt) has its own metadata array and an
/// unbound static-function dispatcher. The dispatchers capture nothing —
/// `register(in:)` passes them by reference, so there's no retain cycle
/// between the server and its installed extensions.
public struct MCPExtensionContribution<Server> {
    public typealias ToolDispatcher = (String, Server, JSONDictionary) async throws -> Encodable & Sendable
    public typealias ResourceDispatcher = (String, Server, JSONDictionary, URL, String?) async throws -> [MCPResourceContent]
    public typealias PromptDispatcher = (String, Server, JSONDictionary) async throws -> [PromptMessage]

    public let toolMetadata: [MCPToolMetadata]
    public let toolDispatcher: ToolDispatcher?

    public let resourceMetadata: [MCPResourceMetadata]
    public let resourceDispatcher: ResourceDispatcher?

    public let promptMetadata: [MCPPromptMetadata]
    public let promptDispatcher: PromptDispatcher?

    public init(
        toolMetadata: [MCPToolMetadata] = [],
        toolDispatcher: ToolDispatcher? = nil,
        resourceMetadata: [MCPResourceMetadata] = [],
        resourceDispatcher: ResourceDispatcher? = nil,
        promptMetadata: [MCPPromptMetadata] = [],
        promptDispatcher: PromptDispatcher? = nil
    ) {
        self.toolMetadata = toolMetadata
        self.toolDispatcher = toolDispatcher
        self.resourceMetadata = resourceMetadata
        self.resourceDispatcher = resourceDispatcher
        self.promptMetadata = promptMetadata
        self.promptDispatcher = promptDispatcher
    }
}
