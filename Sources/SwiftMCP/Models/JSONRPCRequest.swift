//
//  JSONRPCRequest.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

@preconcurrency import AnyCodable

/// JSON-RPC Request structure used for communication with the MCP server
public struct JSONRPCRequest: JSONRPCMessage {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"

        /// The unique identifier for the request
        public var id: Int?

        /// The name of the method to be invoked
        public var method: String

        /// The parameters to be passed to the method, as a dictionary of parameter names to values
        public var params: [String: AnyCodable]?

        /// Public initializer
        public init(jsonrpc: String = "2.0", id: Int? = nil, method: String, params: [String : AnyCodable]? = nil) {
                self.jsonrpc = jsonrpc
                self.id = id
                self.method = method
                self.params = params
        }
}
