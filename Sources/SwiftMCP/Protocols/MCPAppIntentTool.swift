//
//  MCPAppIntentTool.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 19.03.25.
//

#if canImport(AppIntents)
import AppIntents

/// Protocol for AppIntents that expose MCP tool metadata and execution.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public protocol MCPAppIntentTool: AppIntent {
    /// Metadata describing the AppIntent as an MCP tool.
    static var mcpToolMetadata: MCPToolMetadata { get }

    /// Executes the AppIntent using MCP arguments.
    static func mcpPerform(arguments: [String: Sendable]) async throws -> (Encodable & Sendable)

    /// Metadata describing the AppIntent as an MCP tool (instance access).
    var mcpToolMetadata: MCPToolMetadata { get }

    /// Executes the AppIntent using MCP arguments (instance access).
    func mcpPerform(arguments: [String: Sendable]) async throws -> (Encodable & Sendable)
}

@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public extension MCPAppIntentTool {
    var mcpToolMetadata: MCPToolMetadata {
        Self.mcpToolMetadata
    }

    func mcpPerform(arguments: [String: Sendable]) async throws -> (Encodable & Sendable) {
        try await Self.mcpPerform(arguments: arguments)
    }
}
#else
/// Stub protocol for platforms without AppIntents support.
public protocol MCPAppIntentTool {}
#endif
