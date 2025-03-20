//
//  JSONRPCMessage.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation
@preconcurrency import AnyCodable

/// JSON-RPC Request structure used for communication with the MCP server
public struct JSONRPCMessage: Codable, Sendable {
	
	public struct Error: Codable, Sendable {
		public var code: Int
		public var message: String
	}
	
	public var jsonrpc: String = "2.0"
	public var id: Int?
	public var method: String?
	public var params: [String: AnyCodable]?
	public var result: [String: AnyCodable]?

	public var error: Error?
}
