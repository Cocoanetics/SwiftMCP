//
//  JSONRPCInitializeResponse.swift
//  SwiftMCP
//
//  Created by Codex on behalf of OpenAI.
//

import Foundation

/// JSON-RPC Response structure for initialize method
public struct JSONRPCInitializeResponse: JSONRPCMessage {
    /// The JSON-RPC protocol version, always "2.0"
    public var jsonrpc: String = "2.0"
    
    /// The unique identifier for the response
    public var id: Int?
    
    /// The result of the initialize call
    public var result: InitializeResult?
    
    /// The error if the initialize call failed
    public var error: JSONRPCErrorResponse.ErrorPayload?
    
    /// The result structure for initialize
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
        }
    }
}
