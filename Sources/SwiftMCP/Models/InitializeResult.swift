//
//  InitializeResult.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation

/// The result structure for initialize response
public struct InitializeResult: Codable, Sendable {
    /// The protocol version supported by the server
    public let protocolVersion: String

    /// The server's capabilities
    public let capabilities: ServerCapabilities

    /// Information about the server
    public let serverInfo: Implementation

    /// Server identity. The spec models both client and server info as
    /// `Implementation`; this alias preserves the `InitializeResult.ServerInfo`
    /// spelling while unifying onto the full type (name, title, version,
    /// description, icons, websiteUrl).
    public typealias ServerInfo = Implementation

    public init(protocolVersion: String, capabilities: ServerCapabilities, serverInfo: Implementation) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}
