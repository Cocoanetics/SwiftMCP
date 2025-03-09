import Foundation
import AnyCodable

extension JSONRPC {
    /// Represents a JSON-RPC 2.0 notification message (a request without an ID)
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
} 