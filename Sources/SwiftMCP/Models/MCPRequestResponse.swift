import Foundation

/// A struct representing a JSON-RPC request for MCP (Model-Controller-Protocol)
public struct MCPRequest: Codable {
    /// The request identifier
    public let id: Int
    
    /// The method name to be called
    public let method: String
    
    /// Optional parameters for the method
    public let params: [String: String]?
    
    /// Initialize a new MCPRequest
    /// - Parameters:
    ///   - id: The request identifier
    ///   - method: The method name to be called
    ///   - params: Optional parameters for the method
    public init(id: Int, method: String, params: [String: String]? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// A struct representing a JSON-RPC 2.0 request for MCP Inspector
public struct MCPInspectorRequest: Codable {
    /// The JSON-RPC version
    public let jsonrpc: String
    
    /// The request identifier
    public let id: Int
    
    /// The method name to be called
    public let method: String
    
    /// Parameters for the method (can contain any JSON structure)
    public let params: [String: Any]?
    
    /// Coding keys for the MCPInspectorRequest
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params
    }
    
    /// Initialize a new MCPInspectorRequest
    /// - Parameters:
    ///   - jsonrpc: The JSON-RPC version
    ///   - id: The request identifier
    ///   - method: The method name to be called
    ///   - params: Parameters for the method
    public init(jsonrpc: String, id: Int, method: String, params: [String: Any]? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
    
    /// Custom decoder to handle the params field which can contain any JSON structure
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        id = try container.decode(Int.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        
        // For params, we'll decode it as a generic JSON object
        if container.contains(.params) {
            // We'll just store it as nil since we don't need the actual params for now
            params = nil
        } else {
            params = nil
        }
    }
    
    /// Custom encoder to handle the params field
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        
        // We don't need to encode params for now
    }
}

/// A struct representing a JSON-RPC response for MCP (Model-Controller-Protocol)
public struct MCPResponse: Codable {
    /// The response identifier (matching the request)
    public let id: Int
    
    /// The result of the method call
    public let result: [String: String]
    
    /// Initialize a new MCPResponse
    /// - Parameters:
    ///   - id: The response identifier (matching the request)
    ///   - result: The result of the method call
    public init(id: Int, result: [String: String]) {
        self.id = id
        self.result = result
    }
}

/// A struct representing a JSON-RPC error response for MCP (Model-Controller-Protocol)
public struct MCPErrorResponse: Codable {
    /// The response identifier (matching the request)
    public let id: Int
    
    /// The error message
    public let error: String
    
    /// Initialize a new MCPErrorResponse
    /// - Parameters:
    ///   - id: The response identifier (matching the request)
    ///   - error: The error message
    public init(id: Int, error: String) {
        self.id = id
        self.error = error
    }
}

/// Process MCP requests and generate appropriate responses
/// - Parameter request: The MCPRequest to handle
/// - Returns: An optional MCPResponse if the request can be handled
public func handleRequest(_ request: MCPRequest) -> MCPResponse? {
    if request.method == "hello" {
        let name = request.params?["name"] ?? "World"
        return MCPResponse(id: request.id, result: ["message": "Hello, \(name)!"])
    }
    return nil
} 