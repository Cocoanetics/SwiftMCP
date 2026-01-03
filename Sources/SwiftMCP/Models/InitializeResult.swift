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
    public let serverInfo: ServerInfo

    /// Server information structure
    public struct ServerInfo: Codable, Sendable {
        /// The name of the server
        public let name: String

        /// The version of the server
        public let version: String

        /// An optional description of the server
        public let description: String?

        public init(name: String, version: String, description: String? = nil) {
            self.name = name
            self.version = version
            self.description = description
        }
    }

    public init(protocolVersion: String, capabilities: ServerCapabilities, serverInfo: ServerInfo) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
} 
