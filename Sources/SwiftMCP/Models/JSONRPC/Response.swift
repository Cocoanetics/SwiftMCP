import Foundation
import AnyCodable

extension JSONRPC {
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
} 