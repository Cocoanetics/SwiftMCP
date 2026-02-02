//
//  MCPToolAnnotations.swift
//  SwiftMCP
//
//  Created by Orbit on 02.02.26.
//

import Foundation

/// Annotations for MCP tools providing hints about tool behavior (per MCP spec).
///
/// These annotations are optional hints that help clients understand tool behavior.
/// All properties are optional - clients should handle missing values gracefully.
///
/// Example usage:
/// ```swift
/// @MCPTool(readOnlyHint: true)
/// func search(query: String) -> [Result]
///
/// @MCPTool(readOnlyHint: false, destructiveHint: true)
/// func deleteItem(id: String) -> Bool
/// ```
public struct MCPToolAnnotations: Codable, Sendable, Equatable {
    /// If true, the tool does not modify its environment.
    /// A tool with no side effects that only retrieves information.
    public let readOnlyHint: Bool?

    /// If true (and readOnlyHint is false), the tool may perform destructive updates.
    /// Destructive means it deletes or overwrites data that cannot be easily recovered.
    public let destructiveHint: Bool?

    /// If true, calling the tool multiple times with the same arguments
    /// has no additional effect beyond the first call.
    public let idempotentHint: Bool?

    /// If true, the tool may interact with external entities
    /// (people, systems, or the physical world) outside the AI model's context.
    public let openWorldHint: Bool?

    /// Creates a new MCPToolAnnotations instance.
    ///
    /// - Parameters:
    ///   - readOnlyHint: If true, the tool does not modify its environment
    ///   - destructiveHint: If true (and readOnlyHint is false), tool may perform destructive updates
    ///   - idempotentHint: If true, calling multiple times with same args has no additional effect
    ///   - openWorldHint: If true, tool may interact with external entities
    public init(
        readOnlyHint: Bool? = nil,
        destructiveHint: Bool? = nil,
        idempotentHint: Bool? = nil,
        openWorldHint: Bool? = nil
    ) {
        self.readOnlyHint = readOnlyHint
        self.destructiveHint = destructiveHint
        self.idempotentHint = idempotentHint
        self.openWorldHint = openWorldHint
    }

    /// Returns true if all annotation hints are nil (no annotations set)
    public var isEmpty: Bool {
        readOnlyHint == nil &&
        destructiveHint == nil &&
        idempotentHint == nil &&
        openWorldHint == nil
    }
}
