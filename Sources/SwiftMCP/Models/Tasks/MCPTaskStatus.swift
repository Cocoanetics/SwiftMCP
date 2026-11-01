//
//  MCPTaskStatus.swift
//  SwiftMCP
//
//  Task lifecycle statuses from the official `io.modelcontextprotocol/tasks`
//  schema (`2026-07-28`).
//

import Foundation

/// The status of a task under the official Tasks extension.
public enum MCPTaskStatus: String, Codable, Sendable, Equatable {
    /// The request is currently being processed.
    case working

    /// Waiting for client input (`inputRequests` / `tasks/update`).
    case inputRequired = "input_required"

    /// Completed successfully; `result` holds the underlying method result
    /// (including tool results with `isError: true`).
    case completed

    /// Failed due to a JSON-RPC error during execution.
    case failed

    /// Cancelled before completion.
    case cancelled

    /// Whether this status is terminal (no further state transitions expected).
    public var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            return true
        case .working, .inputRequired:
            return false
        }
    }
}
