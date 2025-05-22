//
//  JSONRPCResponse.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

@preconcurrency import AnyCodable

/// JSON-RPC success response structure used for communication with the MCP server
public struct JSONRPCResponse: JSONRPCMessage {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"

        /// The unique identifier matching the request ID
        public var id: Int?

        /// The result of the method invocation, as a dictionary of result fields
        public var result: [String: AnyCodable]?

        /// Public initializer
        public init(jsonrpc: String = "2.0", id: Int? = nil, result: [String: AnyCodable]? = nil) {
                self.jsonrpc = jsonrpc
                self.id = id
                self.result = result
        }
}
