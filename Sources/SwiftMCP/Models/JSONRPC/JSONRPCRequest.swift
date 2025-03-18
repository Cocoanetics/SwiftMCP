import Foundation
import AnyCodable

/// JSON-RPC Request structure used for communication with the MCP server
public struct JSONRPCRequest: Codable {
    public let jsonrpc: String
    public let id: Int?
    public let method: String?
    public let params: [String: AnyCodable]?
    
    public init(jsonrpc: String, id: Int?, method: String?, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
} 
