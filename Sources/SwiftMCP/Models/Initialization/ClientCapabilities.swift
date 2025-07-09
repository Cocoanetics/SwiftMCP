//
//  ClientCapabilities.swift
//  SwiftMCP
//
//  Created by SwiftMCP on 03.04.25.
//

import Foundation
@preconcurrency import AnyCodable

/// Represents the capabilities of an MCP client.
///
/// This struct defines the various capabilities that an MCP client can support,
/// including experimental features, roots, sampling, and other client-side functionality.
/// These capabilities are communicated by clients during initialization to inform servers
/// about what functionalities are available on the client.
public struct ClientCapabilities: Codable, Sendable {
    /// Experimental, non-standard capabilities that the client supports.
    public var experimental: [String: AnyCodable]?

    /// Present if the client supports roots functionality.
    public var roots: RootsCapabilities?

    /// Present if the client supports sampling functionality.
    public var sampling: SamplingCapabilities?

    /// Capabilities related to roots.
    public struct RootsCapabilities: Codable, Sendable {
        /// Whether this client supports notifications for changes to the roots list.
        public var listChanged: Bool?

        public init(listChanged: Bool? = nil) {
            self.listChanged = listChanged
        }
    }

    /// Capabilities related to sampling.
    public struct SamplingCapabilities: Codable, Sendable {
        /// Whether this client supports sampling functionality.
        public var enabled: Bool?

        public init(enabled: Bool? = nil) {
            self.enabled = enabled
        }
    }

    public init(experimental: [String: AnyCodable]? = nil, roots: RootsCapabilities? = nil, sampling: SamplingCapabilities? = nil) {
        self.experimental = experimental
        self.roots = roots
        self.sampling = sampling
    }
} 
