import Foundation

extension JSONRPC {
    /// Represents a JSON-RPC 2.0 request identifier (can be a number or string)
    public enum RequestID: Equatable, Hashable, Codable {
        case number(Int)
        case string(String)
        
        public var stringValue: String {
            switch self {
            case .number(let value):
                return String(value)
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