//
//  JSONRPCMessage.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation
@preconcurrency import AnyCodable

public protocol JSONRPCMessage: Codable, Sendable
{
	var jsonrpc: String { get }
	var id: Int? { get }
}

extension JSONRPCMessage {
	var jsonrpc: String { "2.0" }
}

/// JSON-RPC Request structure used for communication with the MCP server
public struct JSONRPCRequest: JSONRPCMessage {
	
	public var jsonrpc: String = "2.0"
	public var id: Int?
	public var method: String?
	public var params: [String: AnyCodable]?
}

/// JSON-RPC success response structure used for communication with the MCP server
public struct JSONRPCResponse: JSONRPCMessage {
	
	public var jsonrpc: String = "2.0"
	public var id: Int?
	public var result: [String: AnyCodable]?
}

/// JSON-RPC error response structure used for communication with the MCP server
public struct JSONRPCErrorResponse: JSONRPCMessage {
	
	public struct ErrorPayload: Codable, Sendable {
		public var code: Int
		public var message: String
	}

	public var jsonrpc: String = "2.0"
	public var id: Int?

	public var error: ErrorPayload
}
