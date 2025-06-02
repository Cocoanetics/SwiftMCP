//
//  JSONRPCMessage.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

@preconcurrency import AnyCodable

/**
 Enum representing all possible JSON-RPC message types.
 This unifies all JSON-RPC message handling and makes it easier to work with collections
 of mixed message types while still being able to distinguish them in processing loops.
 */
public enum JSONRPCMessage: Codable, Sendable {
    case request(JSONRPCRequestData)
    case response(JSONRPCResponseData)
    case errorResponse(JSONRPCErrorResponseData)
    case emptyResponse(JSONRPCEmptyResponseData)
    case initializeResponse(JSONRPCInitializeResponseData)
    
    // MARK: - Data Structures
    
    /// Data structure for JSON-RPC requests
    public struct JSONRPCRequestData: Codable, Sendable {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"
        
        /// The unique identifier for the request
        public var id: Int?
        
        /// The name of the method to be invoked
        public var method: String
        
        /// The parameters to be passed to the method, as a dictionary of parameter names to values
        public var params: [String: AnyCodable]?
        
        /// Public initializer
        public init(jsonrpc: String = "2.0", id: Int? = nil, method: String, params: [String : AnyCodable]? = nil) {
            self.jsonrpc = jsonrpc
            self.id = id
            self.method = method
            self.params = params
        }
    }
    
    /// Data structure for JSON-RPC success responses
    public struct JSONRPCResponseData: Codable, Sendable {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"
        
        /// The unique identifier matching the request ID
        public var id: Int?
        
        /// The result of the method invocation, as a dictionary of result fields
        public var result: [String: AnyCodable]?
        
        /// Public initializer
        public init(jsonrpc: String = "2.0", id: Int? = nil, result: [String: AnyCodable]? = nil) {
            self.jsonrpc = jsonrpc
            self.id = id
            self.result = result
        }
    }
    
    /// Data structure for JSON-RPC error responses
    public struct JSONRPCErrorResponseData: Codable, Sendable {
        /// Represents the error payload containing error details.
        /// Includes an error code and a descriptive message.
        public struct ErrorPayload: Codable, Sendable {
            /// The numeric error code indicating the type of error
            public var code: Int
            
            /// A human-readable error message describing what went wrong
            public var message: String
            
            public init(code: Int, message: String) {
                self.code = code
                self.message = message
            }
        }
        
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"
        
        /// The unique identifier matching the request ID
        public var id: Int?
        
        /// The error details containing the error code and message
        public var error: ErrorPayload
        
        public init(jsonrpc: String = "2.0", id: Int?, error: ErrorPayload) {
            self.jsonrpc = jsonrpc
            self.id = id
            self.error = error
        }
    }
    
    /// Data structure for empty JSON-RPC responses (like ping responses)
    public struct JSONRPCEmptyResponseData: Codable, Sendable {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"
        
        /// The unique identifier matching the request ID
        public var id: Int?
        
        /// Empty result dictionary
        public var result: [String: AnyCodable] = [:]
        
        public init(jsonrpc: String = "2.0", id: Int?) {
            self.jsonrpc = jsonrpc
            self.id = id
        }
    }
    
    /// Data structure for JSON-RPC initialization responses
    public struct JSONRPCInitializeResponseData: Codable, Sendable {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"
        
        /// The unique identifier for the response
        public var id: Int?
        
        /// The result of the initialize call
        public var result: InitializeResult?
        
        /// The error if the initialize call failed
        public var error: JSONRPCErrorResponseData.ErrorPayload?
        
        /// The result structure for initialize
        public struct InitializeResult: Codable, Sendable {
            /// The protocol version supported by the server
            public let protocolVersion: String
            
            /// The server's capabilities
            public let capabilities: ServerCapabilities
            
            /// Information about the server
            public let serverInfo: ServerInfo
            
            /// Server information structure
            public struct ServerInfo: Codable, Sendable {
                /// The name of the server
                public let name: String
                
                /// The version of the server
                public let version: String
                
                public init(name: String, version: String) {
                    self.name = name
                    self.version = version
                }
            }
            
            public init(protocolVersion: String, capabilities: ServerCapabilities, serverInfo: ServerInfo) {
                self.protocolVersion = protocolVersion
                self.capabilities = capabilities
                self.serverInfo = serverInfo
            }
        }
        
        public init(jsonrpc: String = "2.0", id: Int?, result: InitializeResult? = nil, error: JSONRPCErrorResponseData.ErrorPayload? = nil) {
            self.jsonrpc = jsonrpc
            self.id = id
            self.result = result
            self.error = error
        }
    }
    
    // MARK: - Computed Properties
    
    /// The JSON-RPC protocol version, typically "2.0"
    public var jsonrpc: String {
        switch self {
        case .request(let data): return data.jsonrpc
        case .response(let data): return data.jsonrpc
        case .errorResponse(let data): return data.jsonrpc
        case .emptyResponse(let data): return data.jsonrpc
        case .initializeResponse(let data): return data.jsonrpc
        }
    }
    
    /// The unique identifier for the message, used to correlate requests and responses
    public var id: Int? {
        switch self {
        case .request(let data): return data.id
        case .response(let data): return data.id
        case .errorResponse(let data): return data.id
        case .emptyResponse(let data): return data.id
        case .initializeResponse(let data): return data.id
        }
    }
    
    // MARK: - Convenience Initializers
    
    public static func request(jsonrpc: String = "2.0", id: Int? = nil, method: String, params: [String : AnyCodable]? = nil) -> JSONRPCMessage {
        return .request(JSONRPCRequestData(jsonrpc: jsonrpc, id: id, method: method, params: params))
    }
    
    public static func response(jsonrpc: String = "2.0", id: Int? = nil, result: [String: AnyCodable]? = nil) -> JSONRPCMessage {
        return .response(JSONRPCResponseData(jsonrpc: jsonrpc, id: id, result: result))
    }
    
    public static func errorResponse(jsonrpc: String = "2.0", id: Int?, error: JSONRPCErrorResponseData.ErrorPayload) -> JSONRPCMessage {
        return .errorResponse(JSONRPCErrorResponseData(jsonrpc: jsonrpc, id: id, error: error))
    }
    
    public static func emptyResponse(jsonrpc: String = "2.0", id: Int?) -> JSONRPCMessage {
        return .emptyResponse(JSONRPCEmptyResponseData(jsonrpc: jsonrpc, id: id))
    }
    
    public static func initializeResponse(jsonrpc: String = "2.0", id: Int?, result: JSONRPCInitializeResponseData.InitializeResult? = nil, error: JSONRPCErrorResponseData.ErrorPayload? = nil) -> JSONRPCMessage {
        return .initializeResponse(JSONRPCInitializeResponseData(jsonrpc: jsonrpc, id: id, result: result, error: error))
    }
    
    // MARK: - Codable Implementation
    
    private enum CodingKeys: String, CodingKey {
        case jsonrpc, id, method, params, result, error
    }
    
    private enum NestedKeys: String, CodingKey {
        case protocolVersion
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        // All messages must have jsonrpc
        let jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
        let id = try container.decodeIfPresent(Int.self, forKey: .id)
        
        // Determine message type based on available keys
        if container.contains(.method) {
            // This is a request
            let method = try container.decode(String.self, forKey: .method)
            let params = try container.decodeIfPresent([String: AnyCodable].self, forKey: .params)
            self = .request(JSONRPCRequestData(jsonrpc: jsonrpc, id: id, method: method, params: params))
        } else if container.contains(.error) {
            // This is an error response
            let error = try container.decode(JSONRPCErrorResponseData.ErrorPayload.self, forKey: .error)
            self = .errorResponse(JSONRPCErrorResponseData(jsonrpc: jsonrpc, id: id, error: error))
        } else if container.contains(.result) {
            // This is a result response - need to determine if it's initialize, empty, or regular
            let resultValue = try container.decode(AnyCodable.self, forKey: .result)
            
            // Check if it's an initialize response by looking for protocolVersion in the result
            if let resultDict = resultValue.value as? [String: Any],
               let _ = resultDict["protocolVersion"] as? String {
                let result = try container.decode(JSONRPCInitializeResponseData.InitializeResult.self, forKey: .result)
                self = .initializeResponse(JSONRPCInitializeResponseData(jsonrpc: jsonrpc, id: id, result: result))
            } else if let resultDict = resultValue.value as? [String: Any], resultDict.isEmpty {
                self = .emptyResponse(JSONRPCEmptyResponseData(jsonrpc: jsonrpc, id: id))
            } else {
                let result = try container.decode([String: AnyCodable].self, forKey: .result)
                self = .response(JSONRPCResponseData(jsonrpc: jsonrpc, id: id, result: result))
            }
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to determine JSON-RPC message type"))
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        switch self {
        case .request(let data):
            try container.encode(data.jsonrpc, forKey: .jsonrpc)
            try container.encodeIfPresent(data.id, forKey: .id)
            try container.encode(data.method, forKey: .method)
            try container.encodeIfPresent(data.params, forKey: .params)
            
        case .response(let data):
            try container.encode(data.jsonrpc, forKey: .jsonrpc)
            try container.encodeIfPresent(data.id, forKey: .id)
            try container.encodeIfPresent(data.result, forKey: .result)
            
        case .errorResponse(let data):
            try container.encode(data.jsonrpc, forKey: .jsonrpc)
            try container.encodeIfPresent(data.id, forKey: .id)
            try container.encode(data.error, forKey: .error)
            
        case .emptyResponse(let data):
            try container.encode(data.jsonrpc, forKey: .jsonrpc)
            try container.encodeIfPresent(data.id, forKey: .id)
            try container.encode(data.result, forKey: .result)
            
        case .initializeResponse(let data):
            try container.encode(data.jsonrpc, forKey: .jsonrpc)
            try container.encodeIfPresent(data.id, forKey: .id)
            try container.encodeIfPresent(data.result, forKey: .result)
            try container.encodeIfPresent(data.error, forKey: .error)
        }
    }
}

// MARK: - Backward Compatibility Aliases

/// Backward compatibility alias for JSONRPCRequestData
public typealias JSONRPCRequest = JSONRPCMessage.JSONRPCRequestData

/// Backward compatibility alias for JSONRPCResponseData  
public typealias JSONRPCResponse = JSONRPCMessage.JSONRPCResponseData

/// Backward compatibility alias for JSONRPCErrorResponseData
public typealias JSONRPCErrorResponse = JSONRPCMessage.JSONRPCErrorResponseData

/// Backward compatibility alias for JSONRPCEmptyResponseData
public typealias JSONRPCEmptyResponse = JSONRPCMessage.JSONRPCEmptyResponseData

/// Backward compatibility alias for JSONRPCInitializeResponseData
public typealias JSONRPCInitializeResponse = JSONRPCMessage.JSONRPCInitializeResponseData

// MARK: - Convenience Extensions for Migration

extension JSONRPCMessage {
    /// Creates a request message - convenience for migration
    public static func makeRequest(jsonrpc: String = "2.0", id: Int? = nil, method: String, params: [String : AnyCodable]? = nil) -> JSONRPCMessage {
        return .request(JSONRPCRequestData(jsonrpc: jsonrpc, id: id, method: method, params: params))
    }
    
    /// Creates a response message - convenience for migration
    public static func makeResponse(jsonrpc: String = "2.0", id: Int? = nil, result: [String: AnyCodable]? = nil) -> JSONRPCMessage {
        return .response(JSONRPCResponseData(jsonrpc: jsonrpc, id: id, result: result))
    }
    
    /// Creates an error response message - convenience for migration
    public static func makeErrorResponse(jsonrpc: String = "2.0", id: Int?, error: JSONRPCErrorResponseData.ErrorPayload) -> JSONRPCMessage {
        return .errorResponse(JSONRPCErrorResponseData(jsonrpc: jsonrpc, id: id, error: error))
    }
    
    /// Creates an empty response message - convenience for migration
    public static func makeEmptyResponse(jsonrpc: String = "2.0", id: Int?) -> JSONRPCMessage {
        return .emptyResponse(JSONRPCEmptyResponseData(jsonrpc: jsonrpc, id: id))
    }
    
    /// Creates an initialize response message - convenience for migration
    public static func makeInitializeResponse(jsonrpc: String = "2.0", id: Int?, result: JSONRPCInitializeResponseData.InitializeResult? = nil, error: JSONRPCErrorResponseData.ErrorPayload? = nil) -> JSONRPCMessage {
        return .initializeResponse(JSONRPCInitializeResponseData(jsonrpc: jsonrpc, id: id, result: result, error: error))
    }
}
