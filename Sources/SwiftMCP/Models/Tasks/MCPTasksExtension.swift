//
//  MCPTasksExtension.swift
//  SwiftMCP
//
//  Official Tasks extension (`io.modelcontextprotocol/tasks`) — SEP-2663.
//  Schema pinned at implementation time for #223 from the released
//  `2026-07-28` snapshot (empty capability object; methods `tasks/get`,
//  `tasks/update`, `tasks/cancel`; polymorphic `resultType: "task"` handles;
//  no `tasks/list` / `tasks/result`).
//
//  Spec: https://tasks.extensions.modelcontextprotocol.io/specification/2026-07-28/tasks
//  Schema: https://github.com/modelcontextprotocol/ext-tasks/blob/main/schema/2026-07-28/schema.ts
//

import Foundation

/// Constants for the official MCP Tasks extension.
public enum MCPTasksExtension {
    /// Extension identifier used in the string-keyed `capabilities.extensions` map.
    public static let identifier = "io.modelcontextprotocol/tasks"

    /// Released schema / specification snapshot this implementation targets.
    public static let schemaVersion = "2026-07-28"

    /// Source-of-truth schema URL verified when this extension was implemented.
    public static let schemaSource =
        "https://github.com/modelcontextprotocol/ext-tasks/blob/main/schema/2026-07-28/schema.ts"

    /// Wire capability value — an empty object indicates support; no settings are defined.
    public static let capability: JSONValue = .object([:])

    /// JSON-RPC error code for a missing required client capability (`-32021`).
    public static let missingRequiredClientCapabilityCode = -32021

    /// Default task time-to-live from creation, in milliseconds (1 hour).
    public static let defaultTTLMs: Int = 3_600_000

    /// Default suggested polling interval, in milliseconds.
    public static let defaultPollIntervalMs: Int = 1_000
}
