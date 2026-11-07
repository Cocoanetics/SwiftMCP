//
//  EventDescriptor.swift
//  SwiftMCP
//

import Foundation

/// Describes one event type a server can deliver to subscribers.
public struct EventDescriptor: Codable, Sendable, Equatable {
    /// Programmatic event type name.
    public let name: String

    /// Human-readable description.
    public let description: String?

    /// JSON Schema of the filter a subscriber may pass to narrow the event stream.
    public let inputSchema: JSONSchema?

    /// JSON Schema of the delivered event payload.
    public let payloadSchema: JSONSchema?

    /// Supported delivery modes: a non-empty subset of `"poll"`, `"push"`, `"webhook"`.
    public let delivery: [String]?

    public init(
        name: String,
        description: String? = nil,
        inputSchema: JSONSchema? = nil,
        payloadSchema: JSONSchema? = nil,
        delivery: [String]? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.payloadSchema = payloadSchema
        self.delivery = delivery
    }
}
