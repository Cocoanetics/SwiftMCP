import Foundation
import AnyCodable

/// Namespace for JSON-RPC 2.0 types
public enum JSONRPC {
    /// The JSON-RPC version string
    public static let version = "2.0"
    
    /// Represents a JSON-RPC 2.0 request message
    public struct Request: Codable {
        /// The JSON-RPC version (always "2.0")
        public let jsonrpc: String
        
        /// The request identifier (can be a number or string)
        public let id: RequestID
        
        /// The method name to be called
        public let method: String
        
        /// Optional parameters for the method
        public let params: AnyCodable?
        
        /// Initialize a new request
        /// - Parameters:
        ///   - id: The request identifier
        ///   - method: The method name to be called
        ///   - params: Optional parameters for the method
        public init(id: RequestID, method: String, params: AnyCodable? = nil) {
            self.jsonrpc = JSONRPC.version
            self.id = id
            self.method = method
            self.params = params
        }
    }
    
    /// Represents a JSON-RPC 2.0 response message
    public struct Response: Codable {
        /// The JSON-RPC version (always "2.0")
        public let jsonrpc: String
        
        /// The response identifier (matching the request)
        public let id: RequestID
        
        /// The result of the method call (present on success)
        public let result: AnyCodable?
        
        /// The error information (present on failure)
        public let error: ErrorObject?
        
        /// Initialize a new successful response
        /// - Parameters:
        ///   - id: The response identifier (matching the request)
        ///   - result: The result of the method call
        public init(id: RequestID, result: AnyCodable) {
            self.jsonrpc = JSONRPC.version
            self.id = id
            self.result = result
            self.error = nil
        }
        
        /// Initialize a new error response
        /// - Parameters:
        ///   - id: The response identifier (matching the request)
        ///   - error: The error information
        public init(id: RequestID, error: ErrorObject) {
            self.jsonrpc = JSONRPC.version
            self.id = id
            self.result = nil
            self.error = error
        }
    }
    
    /// Represents a JSON-RPC 2.0 notification message (one-way, no response expected)
    public struct Notification: Codable {
        /// The JSON-RPC version (always "2.0")
        public let jsonrpc: String
        
        /// The method name to be called
        public let method: String
        
        /// Optional parameters for the method
        public let params: AnyCodable?
        
        /// Initialize a new notification
        /// - Parameters:
        ///   - method: The method name to be called
        ///   - params: Optional parameters for the method
        public init(method: String, params: AnyCodable? = nil) {
            self.jsonrpc = JSONRPC.version
            self.method = method
            self.params = params
        }
    }
    
    /// Represents a JSON-RPC 2.0 error object
    public struct ErrorObject: Codable {
        /// The error code
        public let code: Int
        
        /// The error message
        public let message: String
        
        /// Optional additional data about the error
        public let data: AnyCodable?
        
        /// Initialize a new error object
        /// - Parameters:
        ///   - code: The error code
        ///   - message: The error message
        ///   - data: Optional additional data about the error
        public init(code: Int, message: String, data: AnyCodable? = nil) {
            self.code = code
            self.message = message
            self.data = data
        }
    }
    
    /// Predefined error codes as per JSON-RPC 2.0 specification
    public enum ErrorCode {
        /// Invalid JSON was received by the server
        public static let parseError = -32700
        
        /// The JSON sent is not a valid Request object
        public static let invalidRequest = -32600
        
        /// The method does not exist / is not available
        public static let methodNotFound = -32601
        
        /// Invalid method parameter(s)
        public static let invalidParams = -32602
        
        /// Internal JSON-RPC error
        public static let internalError = -32603
        
        /// Reserved for implementation-defined server-errors
        public static let serverErrorStart = -32099
        public static let serverErrorEnd = -32000
    }
    
    /// Request ID type that can be either Int or String
    public enum RequestID: Codable, Equatable, Hashable, CustomStringConvertible {
        case number(Int)
        case string(String)
        
        /// A string representation of the request ID
        public var description: String {
            switch self {
            case .number(let value):
                return "\(value)"
            case .string(let value):
                return value
            }
        }
        
        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            
            if let intValue = try? container.decode(Int.self) {
                self = .number(intValue)
            } else if let stringValue = try? container.decode(String.self) {
                self = .string(stringValue)
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Request ID must be either a number or a string"
                )
            }
        }
        
        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            
            switch self {
            case .number(let value):
                try container.encode(value)
            case .string(let value):
                try container.encode(value)
            }
        }
    }
}

// JSON-RPC Request structure
public struct JSONRPCRequest: Codable {
    public let jsonrpc: String
    public let id: Int
    public let method: String
    public let params: [String: AnyCodable]?
    
    public init(jsonrpc: String, id: Int, method: String, params: [String: AnyCodable]? = nil) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }
    
    // Helper method to access a specific param value
    public func getParamValue(key: String) -> Any? {
        return params?[key]?.value
    }
    
    // Helper method to access a nested param value
    public func getNestedParamValue(path: [String]) -> Any? {
        guard let params = params, !path.isEmpty else { return nil }
        
        // Handle the first level
        guard let firstValue = params[path[0]]?.value else { return nil }
        
        // If path has only one element, return the value
        if path.count == 1 {
            return firstValue
        }
        
        // Handle nested levels
        var current: Any? = firstValue
        
        for i in 1..<path.count {
            if let dict = current as? [String: Any] {
                current = dict[path[i]]
            } else if let dict = current as? [String: AnyCodable] {
                current = dict[path[i]]?.value
            } else {
                return nil // Not a dictionary, can't go deeper
            }
        }
        
        return current
    }
}

// JSON-RPC Response structures
public struct JSONRPCResponse: Codable {
    public var jsonrpc: String = "2.0"
    public let id: Int
    public let result: ResponseResult
    
    public struct ResponseResult: Codable {
        public let protocolVersion: String
        public let capabilities: Capabilities
        public let serverInfo: ServerInfo
        
        public struct Capabilities: Codable {
            public var experimental: [String: String]? = [:]
            public let tools: Tools
            
            public struct Tools: Codable {
                public let listChanged: Bool
            }
        }
        
        public struct ServerInfo: Codable {
            public let name: String
            public let version: String
        }
    }
}

// Tools Response structure
public struct ToolsResponse: Codable {
    public let jsonrpc: String
    public let id: Int
    public let result: ToolsResult
    
    public init(jsonrpc: String = "2.0", id: Int, result: ToolsResult) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.result = result
    }
    
    public struct ToolsResult: Codable {
        public let tools: [Tool]
        
        public struct Tool: Codable {
            public let name: String
            public let description: String
            public let inputSchema: InputSchema
            
            public struct InputSchema: Codable {
                public let type: String
                public let properties: [String: Property]
                public let required: [String]?
                
                public struct Property: Codable {
                    public let type: String
                    public let description: String
                }
            }
        }
    }
} 
