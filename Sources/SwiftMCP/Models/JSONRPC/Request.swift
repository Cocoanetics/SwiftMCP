import Foundation
import AnyCodable

extension JSONRPC {
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
} 