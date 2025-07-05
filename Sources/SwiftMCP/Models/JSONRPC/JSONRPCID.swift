import Foundation

/// Represents the identifier for a JSON-RPC message which may be an integer or a string.
public enum JSONRPCID: Codable, Sendable, Hashable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
        } else if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
        } else {
            throw DecodingError.typeMismatch(JSONRPCID.self,
                                             DecodingError.Context(codingPath: decoder.codingPath,
                                                                  debugDescription: "Expected Int or String for JSON-RPC id"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}
