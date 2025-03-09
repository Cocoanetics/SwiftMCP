import Foundation

// MARK: - JSONRPC Response Model
struct JSONRPCResponse: Encodable {
	let jsonrpc: String = "2.0"
	let id: Int
	let result: ResultData
}

// MARK: - ResultData
struct ResultData: Encodable {
	let protocolVersion: String
	let capabilities: Capabilities
	let serverInfo: ServerInfo
}

// MARK: - Capabilities
struct Capabilities: Encodable {
	let experimental: [String: String] = [:]
	let tools: Tools
}

// MARK: - Tools
struct Tools: Encodable {
	let listChanged: Bool
}

// MARK: - ServerInfo
struct ServerInfo: Encodable {
	let name: String
	let version: String
}
