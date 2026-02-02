//
//  MCPToolHints.swift
//  SwiftMCP
//
//  Created by Orbit on 02.02.26.
//

import Foundation

/// OptionSet representing tool behavior hints for MCP tools (per MCP spec).
///
/// Use this to declare hints about tool behavior that help clients understand
/// how to handle tool invocations.
///
/// Example usage:
/// ```swift
/// @MCPTool(hints: [.readOnly])
/// func search(query: String) -> [Result]
///
/// @MCPTool(hints: [.destructive, .openWorld])
/// func deleteAccount(id: String) -> Bool
///
/// @MCPTool(hints: [.idempotent])
/// func updateSetting(key: String, value: String) -> Bool
/// ```
public struct MCPToolHints: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The tool does not modify its environment - only retrieves information.
    /// A tool with no side effects.
    public static let readOnly = MCPToolHints(rawValue: 1 << 0)

    /// The tool may perform destructive updates (delete/overwrite data).
    /// Only meaningful when `.readOnly` is NOT set.
    public static let destructive = MCPToolHints(rawValue: 1 << 1)

    /// Calling the tool multiple times with the same arguments
    /// has no additional effect beyond the first call.
    public static let idempotent = MCPToolHints(rawValue: 1 << 2)

    /// The tool may interact with external entities
    /// (people, systems, or the physical world) outside the AI model's context.
    public static let openWorld = MCPToolHints(rawValue: 1 << 3)
}
