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
/// Use the OptionSet-based API for cleaner syntax.
///
/// Example usage:
/// ```swift
/// @MCPTool(hints: [.readOnly])
/// func search(query: String) -> [Result]
///
/// @MCPTool(hints: [.destructive, .openWorld])
/// func deleteAccount(id: String) -> Bool
/// ```
public struct MCPToolAnnotations: Sendable, Equatable {
    /// The underlying hints as an OptionSet
    public let hints: MCPToolHints

    /// Creates annotations from an OptionSet of hints
    public init(hints: MCPToolHints) {
        self.hints = hints
    }

    /// Creates annotations from individual Bool? values (backwards compatibility)
    public init(
        readOnlyHint: Bool? = nil,
        destructiveHint: Bool? = nil,
        idempotentHint: Bool? = nil,
        openWorldHint: Bool? = nil
    ) {
        var hints = MCPToolHints()
        if readOnlyHint == true { hints.insert(.readOnly) }
        if destructiveHint == true { hints.insert(.destructive) }
        if idempotentHint == true { hints.insert(.idempotent) }
        if openWorldHint == true { hints.insert(.openWorld) }
        self.hints = hints
    }

    /// Returns true if no hints are set
    public var isEmpty: Bool {
        hints.isEmpty
    }

    // MARK: - Convenience Accessors (for backwards compatibility and JSON encoding)

    /// If true, the tool does not modify its environment
    public var readOnlyHint: Bool? {
        hints.contains(.readOnly) ? true : nil
    }

    /// If true (and readOnlyHint is false), the tool may perform destructive updates
    public var destructiveHint: Bool? {
        hints.contains(.destructive) ? true : nil
    }

    /// If true, calling multiple times with same args has no additional effect
    public var idempotentHint: Bool? {
        hints.contains(.idempotent) ? true : nil
    }

    /// If true, tool may interact with external entities
    public var openWorldHint: Bool? {
        hints.contains(.openWorld) ? true : nil
    }
}

// MARK: - Codable (custom implementation for MCP JSON wire format)

extension MCPToolAnnotations: Codable {
    private enum CodingKeys: String, CodingKey {
        case readOnlyHint
        case destructiveHint
        case idempotentHint
        case openWorldHint
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        var hints = MCPToolHints()

        if try container.decodeIfPresent(Bool.self, forKey: .readOnlyHint) == true {
            hints.insert(.readOnly)
        }
        if try container.decodeIfPresent(Bool.self, forKey: .destructiveHint) == true {
            hints.insert(.destructive)
        }
        if try container.decodeIfPresent(Bool.self, forKey: .idempotentHint) == true {
            hints.insert(.idempotent)
        }
        if try container.decodeIfPresent(Bool.self, forKey: .openWorldHint) == true {
            hints.insert(.openWorld)
        }

        self.hints = hints
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Only encode hints that are set (true), omit others for clean JSON
        if hints.contains(.readOnly) {
            try container.encode(true, forKey: .readOnlyHint)
        }
        if hints.contains(.destructive) {
            try container.encode(true, forKey: .destructiveHint)
        }
        if hints.contains(.idempotent) {
            try container.encode(true, forKey: .idempotentHint)
        }
        if hints.contains(.openWorld) {
            try container.encode(true, forKey: .openWorldHint)
        }
    }
}

// MARK: - Factory Methods

extension MCPToolAnnotations {
    /// Creates annotations for a read-only tool
    public static var readOnly: MCPToolAnnotations {
        MCPToolAnnotations(hints: [.readOnly])
    }

    /// Creates annotations for a destructive tool
    public static var destructive: MCPToolAnnotations {
        MCPToolAnnotations(hints: [.destructive])
    }
}
