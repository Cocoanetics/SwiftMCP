//
//  JSONRPCMessage.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation
@preconcurrency import AnyCodable

/**
 Protocol defining the common properties for all JSON-RPC messages.
 All JSON-RPC messages must conform to this protocol and provide a JSON-RPC version
 and an optional message ID.
 */
public protocol JSONRPCMessage: Codable, Sendable
{
	/** The JSON-RPC protocol version, typically "2.0" */
	var jsonrpc: String { get }
	
	/** The unique identifier for the message, used to correlate requests and responses */
	var id: Int? { get }
}

/// JSON-RPC Request structure used for communication with the MCP server
/**
 Represents a JSON-RPC request message used for communication with the MCP server.
 This structure encapsulates the method to be called and its parameters.
 */
public struct JSONRPCRequest: JSONRPCMessage {
	
	/** The JSON-RPC protocol version, always "2.0" */
	public var jsonrpc: String = "2.0"
	
	/** The unique identifier for the request */
	public var id: Int?
	
	/** The name of the method to be invoked */
	public var method: String?
	
	/** The parameters to be passed to the method, as a dictionary of parameter names to values */
	public var params: [String: AnyCodable]?
}

/// JSON-RPC success response structure used for communication with the MCP server
/**
 Represents a successful JSON-RPC response message from the MCP server.
 This structure contains the result of the method invocation.
 */
public struct JSONRPCResponse: JSONRPCMessage {
	
	/** The JSON-RPC protocol version, always "2.0" */
	public var jsonrpc: String = "2.0"
	
	/** The unique identifier matching the request ID */
	public var id: Int?
	
	/** The result of the method invocation, as a dictionary of result fields */
	public var result: [String: AnyCodable]?
}

/// JSON-RPC error response structure used for communication with the MCP server
/**
 Represents an error response from the MCP server.
 This structure contains detailed error information when a method invocation fails.
 */
public struct JSONRPCErrorResponse: JSONRPCMessage {
	
	/**
	 Represents the error payload containing error details.
	 Includes an error code and a descriptive message.
	 */
	public struct ErrorPayload: Codable, Sendable {
		/** The numeric error code indicating the type of error */
		public var code: Int
		
		/** A human-readable error message describing what went wrong */
		public var message: String
	}

	/** The JSON-RPC protocol version, always "2.0" */
	public var jsonrpc: String = "2.0"
	
	/** The unique identifier matching the request ID */
	public var id: Int?

	/** The error details containing the error code and message */
	public var error: ErrorPayload
}
