//
//  ClientCapabilities.swift
//  SwiftMCP
//
//  Created by SwiftMCP on 03.04.25.
//

import Foundation

/// Represents the capabilities of an MCP client.
///
/// This struct defines the various capabilities that an MCP client can support,
/// including experimental features, roots, sampling, and other client-side functionality.
/// These capabilities are communicated by clients during initialization to inform servers
/// about what functionalities are available on the client.
public struct ClientCapabilities: Codable, Sendable {
    /// Experimental, non-standard capabilities that the client supports.
    public var experimental: JSONDictionary?

    /// Present if the client supports roots functionality.
    public var roots: RootsCapabilities?

    /// Present if the client supports sampling functionality.
    public var sampling: SamplingCapabilities?

    /// Present if the client supports elicitation functionality.
    public var elicitation: ElicitationCapabilities?

    /// Negotiated protocol extensions the client supports, keyed by their
    /// `io.modelcontextprotocol/...` identifier. The open-ended negotiation seam
    /// introduced for the modern era; omitted when the client declares none.
    public var extensions: JSONDictionary?

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
        public init() {}
    }

    /// Capabilities related to elicitation.
    public struct ElicitationCapabilities: Codable, Sendable {
        public init() {}
    }

    public init(
        experimental: JSONDictionary? = nil,
        roots: RootsCapabilities? = nil,
        sampling: SamplingCapabilities? = nil,
        elicitation: ElicitationCapabilities? = nil,
        extensions: JSONDictionary? = nil
    ) {
        self.experimental = experimental
        self.roots = roots
        self.sampling = sampling
        self.elicitation = elicitation
        self.extensions = extensions
    }
}
