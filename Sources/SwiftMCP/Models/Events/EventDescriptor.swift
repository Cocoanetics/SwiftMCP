//
//  EventDescriptor.swift
//  SwiftMCP
//

import Foundation

/// Describes one event type a server can deliver to subscribers.
public struct EventDescriptor: Codable, Sendable, Equatable {
    /// Delivery mechanisms an event type supports (e.g. `"webhook"`).
    public struct Delivery: Codable, Sendable, Equatable {
        /// Supported delivery modes.
        public let modes: [String]

        public init(modes: [String]) {
            self.modes = modes
        }
    }

    /// Programmatic event type name.
    public let name: String

    /// Human-readable description.
    public let description: String?

    /// JSON Schema of the filter a subscriber may pass to narrow the event stream.
    public let inputSchema: JSONSchema?

    /// JSON Schema of the delivered event payload.
    public let payloadSchema: JSONSchema?

    /// Supported delivery options.
    public let delivery: Delivery?

    public init(
        name: String,
        description: String? = nil,
        inputSchema: JSONSchema? = nil,
        payloadSchema: JSONSchema? = nil,
        delivery: Delivery? = nil
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.payloadSchema = payloadSchema
        self.delivery = delivery
    }
}
