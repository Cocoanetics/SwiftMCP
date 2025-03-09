import Foundation
import AnyCodable

extension JSONRPC {
    /// Represents a JSON-RPC 2.0 error object
    public struct ErrorObject: Codable, Error {
        /// The error code
        public let code: Int
        
        /// The error message
        public let message: String
        
        /// Additional error data (optional)
        public let data: AnyCodable?
        
        /// Initialize a new error object
        /// - Parameters:
        ///   - code: The error code
        ///   - message: The error message
        ///   - data: Additional error data (optional)
        public init(code: Int, message: String, data: AnyCodable? = nil) {
            self.code = code
            self.message = message
            self.data = data
        }
        
        /// Initialize a new error object from a predefined error code
        /// - Parameters:
        ///   - code: The predefined error code
        ///   - data: Additional error data (optional)
        public init(code: ErrorCode, data: AnyCodable? = nil) {
            self.code = code.rawValue
            self.message = code.message
            self.data = data
        }
    }
    
    /// Predefined JSON-RPC 2.0 error codes
    public enum ErrorCode: Int {
        /// Invalid JSON was received by the server
        case parseError = -32700
        /// The JSON sent is not a valid Request object
        case invalidRequest = -32600
        /// The method does not exist / is not available
        case methodNotFound = -32601
        /// Invalid method parameter(s)
        case invalidParams = -32602
        /// Internal JSON-RPC error
        case internalError = -32603
        /// Reserved for implementation-defined server-errors
        case serverError = -32000
        
        /// The error message for this error code
        public var message: String {
            switch self {
            case .parseError:
                return "Parse error"
            case .invalidRequest:
                return "Invalid Request"
            case .methodNotFound:
                return "Method not found"
            case .invalidParams:
                return "Invalid params"
            case .internalError:
                return "Internal error"
            case .serverError:
                return "Server error"
            }
        }
    }
} 