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
    case notification(JSONRPCNotificationData)
    case response(JSONRPCResponseData)
    case errorResponse(JSONRPCErrorResponseData)

    // MARK: - Data Structures

    /// Data structure for JSON-RPC requests (with ID, expecting response)
    public struct JSONRPCRequestData: Codable, Sendable {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"

        /// The unique identifier for the request (non-optional for requests expecting responses)
        public var id: JSONRPCID

        /// The name of the method to be invoked
        public var method: String

        /// The parameters to be passed to the method, as a dictionary of parameter names to values
        public var params: [String: AnyCodable]?

        /// Public initializer
        public init(jsonrpc: String = "2.0", id: JSONRPCID, method: String, params: [String : AnyCodable]? = nil) {
            self.jsonrpc = jsonrpc
            self.id = id
            self.method = method
            self.params = params
        }
    }

    /// Data structure for JSON-RPC notifications (no ID, no response expected)
    public struct JSONRPCNotificationData: Codable, Sendable {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"

        /// The name of the method to be invoked
        public var method: String

        /// The parameters to be passed to the method, as a dictionary of parameter names to values
        public var params: [String: AnyCodable]?

        /// Public initializer
        public init(jsonrpc: String = "2.0", method: String, params: [String : AnyCodable]? = nil) {
            self.jsonrpc = jsonrpc
            self.method = method
            self.params = params
        }
    }

    /// Data structure for JSON-RPC success responses
    public struct JSONRPCResponseData: Codable, Sendable {
        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"

        /// The unique identifier matching the request ID (non-optional for responses)
        public var id: JSONRPCID

        /// The result of the method invocation, as a dictionary of result fields
        public var result: [String: AnyCodable]?

        /// Public initializer
        public init(jsonrpc: String = "2.0", id: JSONRPCID, result: [String: AnyCodable]? = nil) {
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

            /// Optional structured data with additional error details
            public var data: [String: AnyCodable]?

            public init(code: Int, message: String, data: [String: AnyCodable]? = nil) {
                self.code = code
                self.message = message
                self.data = data
            }
        }

        /// The JSON-RPC protocol version, always "2.0"
        public var jsonrpc: String = "2.0"

        /// The unique identifier matching the request ID
        public var id: JSONRPCID?

        /// The error details containing the error code and message
        public var error: ErrorPayload

        public init(jsonrpc: String = "2.0", id: JSONRPCID?, error: ErrorPayload) {
            self.jsonrpc = jsonrpc
            self.id = id
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
            case .notification(let data): return data.jsonrpc
        }
    }

    /// The unique identifier for the message, used to correlate requests and responses
    public var id: JSONRPCID? {
        switch self {
            case .request(let data): return data.id
            case .response(let data): return data.id
            case .errorResponse(let data): return data.id
            case .notification(_): return nil
        }
    }

    // MARK: - Convenience Initializers

    public static func request(jsonrpc: String = "2.0", id: JSONRPCID, method: String, params: [String : AnyCodable]? = nil) -> JSONRPCMessage {
        return .request(JSONRPCRequestData(jsonrpc: jsonrpc, id: id, method: method, params: params))
    }

    public static func request(jsonrpc: String = "2.0", id: Int, method: String, params: [String : AnyCodable]? = nil) -> JSONRPCMessage {
        request(jsonrpc: jsonrpc, id: .int(id), method: method, params: params)
    }

    public static func request(jsonrpc: String = "2.0", id: String, method: String, params: [String : AnyCodable]? = nil) -> JSONRPCMessage {
        request(jsonrpc: jsonrpc, id: .string(id), method: method, params: params)
    }

    public static func response(jsonrpc: String = "2.0", id: JSONRPCID, result: [String: AnyCodable]? = nil) -> JSONRPCMessage {
        return .response(JSONRPCResponseData(jsonrpc: jsonrpc, id: id, result: result))
    }

    public static func response(jsonrpc: String = "2.0", id: Int, result: [String: AnyCodable]? = nil) -> JSONRPCMessage {
        response(jsonrpc: jsonrpc, id: .int(id), result: result)
    }

    public static func response(jsonrpc: String = "2.0", id: String, result: [String: AnyCodable]? = nil) -> JSONRPCMessage {
        response(jsonrpc: jsonrpc, id: .string(id), result: result)
    }

    public static func errorResponse(jsonrpc: String = "2.0", id: JSONRPCID?, error: JSONRPCErrorResponseData.ErrorPayload) -> JSONRPCMessage {
        return .errorResponse(JSONRPCErrorResponseData(jsonrpc: jsonrpc, id: id, error: error))
    }

    public static func notification(jsonrpc: String = "2.0", method: String, params: [String : AnyCodable]? = nil) -> JSONRPCMessage {
        return .notification(JSONRPCNotificationData(jsonrpc: jsonrpc, method: method, params: params))
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
        let id = try container.decodeIfPresent(JSONRPCID.self, forKey: .id)

        // Determine message type based on available keys
        if container.contains(.method) {
            // This is a request or notification
            let method = try container.decode(String.self, forKey: .method)
            let params = try container.decodeIfPresent([String: AnyCodable].self, forKey: .params)

            if let id = id {
                // Request with ID (expecting response)
                self = .request(JSONRPCRequestData(jsonrpc: jsonrpc, id: id, method: method, params: params))
            } else {
                // Notification without ID (no response expected)
                self = .notification(JSONRPCNotificationData(jsonrpc: jsonrpc, method: method, params: params))
            }
        } else if container.contains(.error) {
            // This is an error response
            let error = try container.decode(JSONRPCErrorResponseData.ErrorPayload.self, forKey: .error)
            self = .errorResponse(JSONRPCErrorResponseData(jsonrpc: jsonrpc, id: id, error: error))
        } else if container.contains(.result) {
            // This is a result response - must have ID
            guard let id = id else {
                throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Response missing required id field"))
            }

            // Handle both empty and non-empty result dictionaries as regular responses
            let result = try container.decode([String: AnyCodable].self, forKey: .result)
            self = .response(JSONRPCResponseData(jsonrpc: jsonrpc, id: id, result: result))
        } else {
            throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unable to determine JSON-RPC message type"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
            case .request(let data):
                try container.encode(data.jsonrpc, forKey: .jsonrpc)
                try container.encode(data.id, forKey: .id)
                try container.encode(data.method, forKey: .method)
                try container.encodeIfPresent(data.params, forKey: .params)

            case .notification(let data):
                try container.encode(data.jsonrpc, forKey: .jsonrpc)
                try container.encode(data.method, forKey: .method)
                try container.encodeIfPresent(data.params, forKey: .params)

            case .response(let data):
                try container.encode(data.jsonrpc, forKey: .jsonrpc)
                try container.encode(data.id, forKey: .id)
                try container.encodeIfPresent(data.result, forKey: .result)

            case .errorResponse(let data):
                try container.encode(data.jsonrpc, forKey: .jsonrpc)
                try container.encodeIfPresent(data.id, forKey: .id)
                try container.encode(data.error, forKey: .error)
        }
    }
}
