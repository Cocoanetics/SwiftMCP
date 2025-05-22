//
//  JSONRPCMessage.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//


/**
 Protocol defining the common properties for all JSON-RPC messages.
 All JSON-RPC messages must conform to this protocol and provide a JSON-RPC version
 and an optional message ID.
 */
public protocol JSONRPCMessage: Codable, Sendable {
        /// The JSON-RPC protocol version, typically "2.0"
        var jsonrpc: String { get }

        /// The unique identifier for the message, used to correlate requests and responses
        var id: Int? { get }
}
