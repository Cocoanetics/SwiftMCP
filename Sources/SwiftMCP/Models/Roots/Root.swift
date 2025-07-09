//
//  Root.swift
//  SwiftMCP
//
//  Created by SwiftMCP on 03.04.25.
//

import Foundation

/// Represents a filesystem root that defines the boundaries of where servers can operate.
///
/// A root provides context about which directories and files the server has access to.
/// This allows servers to understand the client's available resources and adjust their
/// behavior accordingly.
public struct Root: Codable, Sendable, Hashable {
    /// Unique identifier for the root. This MUST be a `file://` URI in the current specification.
    public let uri: String
    
    /// Optional human-readable name for display purposes.
    public let name: String?
    
    /// Creates a new root.
    /// - Parameters:
    ///   - uri: The URI identifying the root location. Must be a `file://` URI.
    ///   - name: Optional human-readable name for the root.
    public init(uri: String, name: String? = nil) {
        self.uri = uri
        self.name = name
    }
}
