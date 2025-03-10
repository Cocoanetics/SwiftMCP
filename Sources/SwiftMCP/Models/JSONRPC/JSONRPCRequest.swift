import Foundation
import AnyCodable

/// JSON-RPC Request structure used for communication with the MCP server
public struct JSONRPCRequest: Codable {
    public let jsonrpc: String
    public let id: Int?
    public let method: String
    public let params: [String: AnyCodable]?
    
    public init(jsonrpc: String, id: Int?, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
    
    /// Gets a parameter value by key
    /// - Parameter key: The key to look up
    /// - Returns: The parameter value, or nil if not found
    public func getParamValue(key: String) -> Any? {
        return params?[key]?.value
    }
    
    /// Gets a nested parameter value by path
    /// - Parameter path: The path to the nested value
    /// - Returns: The nested parameter value, or nil if not found
    public func getNestedParamValue(path: [String]) -> Any? {
        guard !path.isEmpty, let params = params else { return nil }
        
        var current: Any? = params
        
        for key in path {
            if let dict = current as? [String: AnyCodable] {
                current = dict[key]?.value
            } else if let dict = current as? [String: Any] {
                current = dict[key]
            } else {
                return nil
            }
        }
        
        return current
    }
} 
