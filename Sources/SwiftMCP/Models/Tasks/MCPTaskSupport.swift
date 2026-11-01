//
//  MCPTaskSupport.swift
//  SwiftMCP
//
//  Server-side per-tool opt-in for the official Tasks extension. The wire
//  `execution.taskSupport` field from the superseded `2025-11-25` experimental
//  tasks feature is intentionally not resurrected — under SEP-2663 the server
//  decides unsolicited whether to return a task handle once the client has
//  declared `io.modelcontextprotocol/tasks`.
//

import Foundation

/// Whether a tool may (or must) be served as an asynchronous task when the
/// client has negotiated the Tasks extension.
public enum MCPTaskSupport: String, Codable, Sendable, Equatable {
    /// Never return a task handle for this tool (default).
    case forbidden

    /// May return a `CreateTaskResult` when the client declares the Tasks extension;
    /// otherwise runs as a normal synchronous `tools/call`.
    case optional

    /// Must return a task handle. Clients that omit the Tasks extension receive
    /// `-32021` (Missing Required Client Capability).
    case required
}
