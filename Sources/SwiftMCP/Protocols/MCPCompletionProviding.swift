//
//  MCPCompletionProviding.swift
//  SwiftMCP
//
//  Created by Codex.
//

import Foundation

/// Describes the context for which completion values should be provided.
public enum MCPCompletionContext: Sendable {
    case resource(MCPResourceMetadata)
    case prompt(MCPPromptMetadata)
}

/// Protocol for providing completions for argument values.
public protocol MCPCompletionProviding: MCPService {
    /// Returns completion values for the given parameter in the provided context.
    /// - Parameters:
    ///   - parameter: The parameter for which a completion is requested.
    ///   - context: The prompt or resource context.
    ///   - prefix: The prefix string already entered by the client.
    func completion(for parameter: MCPParameterInfo, in context: MCPCompletionContext, prefix: String) async -> CompleteResult.Completion
}

public extension MCPCompletionProviding {
    /// Default implementation that mirrors the behaviour of `MCPParameterInfo.defaultCompletion(prefix:)`.
    func completion(for parameter: MCPParameterInfo, in context: MCPCompletionContext, prefix: String) async -> CompleteResult.Completion {
        return parameter.defaultCompletion(prefix: prefix)
    }
}
