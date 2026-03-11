import Foundation

@usableFromInline
indirect enum _AnyCodableValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case integer(Int)
    case unsignedInteger(UInt)
    case double(Double)
    case string(String)
    case array([_AnyCodableValue])
    case object([String: _AnyCodableValue])

    @usableFromInline
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(UInt.self) {
            self = .unsignedInteger(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([_AnyCodableValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: _AnyCodableValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    @usableFromInline
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .integer(let value):
            try container.encode(value)
        case .unsignedInteger(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    @usableFromInline
    static func make(from value: Any?) -> _AnyCodableValue {
        do {
            return try makeThrowing(from: value)
        } catch {
            preconditionFailure(String(describing: error))
        }
    }

    private static func makeThrowing(from value: Any?) throws -> _AnyCodableValue {
        guard let unwrapped = unwrapOptional(value) else {
            return .null
        }

        switch unwrapped {
        case let value as _AnyCodableValue:
            return value
        case let value as AnyCodable:
            return value.storage
        case let value as AnyEncodable:
            return value.storage
        case let value as AnyDecodable:
            return value.storage
        case is NSNull:
            return .null
        case let value as Bool:
            return .bool(value)
        case let value as Int:
            return .integer(value)
        case let value as Int8:
            return .integer(Int(value))
        case let value as Int16:
            return .integer(Int(value))
        case let value as Int32:
            return .integer(Int(value))
        case let value as Int64:
            if let exact = Int(exactly: value) {
                return .integer(exact)
            }
            return try encodeAndDecode(value)
        case let value as UInt:
            return .unsignedInteger(value)
        case let value as UInt8:
            return .unsignedInteger(UInt(value))
        case let value as UInt16:
            return .unsignedInteger(UInt(value))
        case let value as UInt32:
            return .unsignedInteger(UInt(value))
        case let value as UInt64:
            if let exact = UInt(exactly: value) {
                return .unsignedInteger(exact)
            }
            return try encodeAndDecode(value)
        case let value as Float:
            return .double(Double(value))
        case let value as Double:
            return .double(value)
        case let value as String:
            return .string(value)
        case let value as [AnyCodable]:
            return .array(value.map(\.storage))
        case let value as [AnyEncodable]:
            return .array(value.map(\.storage))
        case let value as [AnyDecodable]:
            return .array(value.map(\.storage))
        case let value as [String: AnyCodable]:
            return .object(value.mapValues(\.storage))
        case let value as [String: AnyEncodable]:
            return .object(value.mapValues(\.storage))
        case let value as [String: AnyDecodable]:
            return .object(value.mapValues(\.storage))
        case let value as [Any?]:
            return .array(try value.map { try makeThrowing(from: $0) })
        case let value as [Any]:
            return .array(try value.map { try makeThrowing(from: $0) })
        case let value as [String: Any?]:
            return .object(try value.mapValues { try makeThrowing(from: $0) })
        case let value as [String: Any]:
            return .object(try value.mapValues { try makeThrowing(from: $0) })
        case let value as any Encodable:
            return try encodeAndDecode(value)
        default:
            throw _AnyCodableConversionError.unsupported(type: Swift.type(of: unwrapped))
        }
    }

    private static func encodeAndDecode(_ value: any Encodable) throws -> _AnyCodableValue {
        let data = try JSONEncoder().encode(_OpaqueEncodable(value))
        return try JSONDecoder().decode(_AnyCodableValue.self, from: data)
    }

    private static func unwrapOptional(_ value: Any?) -> Any? {
        guard let value else {
            return nil
        }

        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }

        guard let child = mirror.children.first else {
            return nil
        }

        return unwrapOptional(child.value)
    }

    @usableFromInline
    var value: Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .integer(let value):
            return value
        case .unsignedInteger(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let value):
            return value.map(\.value)
        case .object(let value):
            return value.mapValues(\.value)
        }
    }

    @usableFromInline
    var sendableValue: any Sendable {
        switch self {
        case .null:
            return ()
        case .bool(let value):
            return value
        case .integer(let value):
            return value
        case .unsignedInteger(let value):
            return value
        case .double(let value):
            return value
        case .string(let value):
            return value
        case .array(let value):
            return value.map(\.sendableValue)
        case .object(let value):
            return value.mapValues(\.sendableValue)
        }
    }

    @usableFromInline
    var arrayValue: [Any]? {
        guard case .array(let value) = self else {
            return nil
        }

        return value.map(\.value)
    }

    @usableFromInline
    var dictionaryValue: [String: Any]? {
        guard case .object(let value) = self else {
            return nil
        }

        return value.mapValues(\.value)
    }

    @usableFromInline
    var sendableDictionaryValue: [String: any Sendable]? {
        guard case .object(let value) = self else {
            return nil
        }

        return value.mapValues(\.sendableValue)
    }

    @usableFromInline
    var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }

        return value
    }

    @usableFromInline
    var boolValue: Bool? {
        guard case .bool(let value) = self else {
            return nil
        }

        return value
    }

    @usableFromInline
    var intValue: Int? {
        guard case .integer(let value) = self else {
            return nil
        }

        return value
    }

    @usableFromInline
    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .integer(let value):
            return Double(value)
        case .unsignedInteger(let value):
            return Double(value)
        default:
            return nil
        }
    }

    @usableFromInline
    func decoded<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        let data = try JSONEncoder().encode(self)
        return try decoder.decode(T.self, from: data)
    }
}

extension _AnyCodableValue: CustomStringConvertible {
    @usableFromInline
    var description: String {
        switch self {
        case .null:
            return String(describing: nil as Any?)
        default:
            return String(describing: value)
        }
    }
}

extension _AnyCodableValue: CustomDebugStringConvertible {
    @usableFromInline
    var debugDescription: String {
        String(reflecting: value)
    }
}

private enum _AnyCodableConversionError: Error, CustomStringConvertible {
    case unsupported(type: Any.Type)

    var description: String {
        switch self {
        case .unsupported(let type):
            return "AnyCodable only supports JSON-compatible or Encodable values; received \(type)"
        }
    }
}

private struct _OpaqueEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeImpl = value.encode(to:)
    }

    @usableFromInline
    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}
