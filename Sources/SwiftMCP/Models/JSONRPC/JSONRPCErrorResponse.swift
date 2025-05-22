//
//  JSONRPCErrorResponse.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

/// JSON-RPC error response structure used for communication with the MCP server
public struct JSONRPCErrorResponse: JSONRPCMessage {
        /// Represents the error payload containing error details.
        /// Includes an error code and a descriptive message.
        public struct ErrorPayload: Codable, Sendable {
                /// The numeric error code indicating the type of error
                public var code: Int

                /// A human-readable error message describing what went wrong
                public var message: String
        }

        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"

        /// The unique identifier matching the request ID
        public var id: Int?

        /// The error details containing the error code and message
        public var error: ErrorPayload
}
