//
//  JSONRPCResponse.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 09.03.25.
//

import Foundation

// MARK: - JSON-RPC Structures

// JSON-RPC Request structure
struct JSONRPCRequest: Codable {
	let jsonrpc: String
	let id: Int
	let method: String
	let params: [String: String]?
}

// JSON-RPC Response structures
struct JSONRPCResponse: Codable {
	var jsonrpc: String = "2.0"
	let id: Int
	let result: ResponseResult
	
	struct ResponseResult: Codable {
		let protocolVersion: String
		let capabilities: Capabilities
		let serverInfo: ServerInfo
		
		struct Capabilities: Codable {
			var experimental: [String: String]? = [:]
			let tools: Tools
			
			struct Tools: Codable {
				let listChanged: Bool
			}
		}
		
		struct ServerInfo: Codable {
			let name: String
			let version: String
		}
	}
}

// Tools Response structure
struct ToolsResponse: Codable {
	let jsonrpc: String
	let id: Int
	let result: ToolsResult
	
	init(jsonrpc: String = "2.0", id: Int, result: ToolsResult) {
		self.jsonrpc = jsonrpc
		self.id = id
		self.result = result
	}
	
	struct ToolsResult: Codable {
		let tools: [Tool]
		
		struct Tool: Codable {
			let name: String
			let description: String
			let inputSchema: InputSchema
			
			struct InputSchema: Codable {
				let type: String
				let properties: [String: Property]
				let required: [String]?
				
				struct Property: Codable {
					let type: String
					let description: String
				}
			}
		}
	}
}
