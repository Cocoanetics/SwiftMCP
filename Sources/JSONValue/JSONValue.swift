import Foundation

public typealias JSONDictionary = [String: JSONValue]
public typealias JSONArray = [JSONValue]

public enum JSONValueError: Error, LocalizedError {
    case expectedObject
    case invalidJSONObject

    public var errorDescription: String? {
        switch self {
        case .expectedObject:
            return "Expected a top-level JSON object."
        case .invalidJSONObject:
            return "Value is not a valid JSON object."
        }
    }
}

public enum MCPJSONCoding {
    public static func makeValueEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601WithTimeZone
        encoder.dataEncodingStrategy = .base64
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return encoder
    }

    public static func makeWireEncoder() -> JSONEncoder {
        let encoder = makeValueEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithTimeZone
        decoder.dataDecodingStrategy = .base64
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}

@frozen public indirect enum JSONValue: Codable, Sendable, Hashable {
    case null
    case bool(Bool)
    case integer(Int)
    case unsignedInteger(UInt)
    case double(Double)
    case string(String)
    case array(JSONArray)
    case object(JSONDictionary)

    public init(from decoder: Decoder) throws {
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
        } else if let value = try? container.decode(JSONArray.self) {
            self = .array(value)
        } else if let value = try? container.decode(JSONDictionary.self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "JSON value cannot be decoded"
            )
        }
    }

    public init<T: Encodable>(encoding value: T, using encoder: JSONEncoder = MCPJSONCoding.makeValueEncoder()) throws {
        let data = try encoder.encode(value)
        self = try MCPJSONCoding.makeDecoder().decode(JSONValue.self, from: data)
    }

    public init(encoding value: any Encodable, using encoder: JSONEncoder = MCPJSONCoding.makeValueEncoder()) throws {
        if let data = value as? Data {
            self = .string(data.base64EncodedString())
            return
        }

        if let values = value as? [Data] {
            self = .array(values.map { .string($0.base64EncodedString()) })
            return
        }

        let data = try encoder.encode(_JSONValueOpaqueEncodable(value))
        self = try MCPJSONCoding.makeDecoder().decode(JSONValue.self, from: data)
    }

    package init(jsonObject value: Any?) throws {
        guard let value else {
            self = .null
            return
        }

        if let result = Self.matchJSONValueOrNull(value) {
            self = result
            return
        }
        if let result = try Self.matchIntegerJSONObject(value) {
            self = result
            return
        }
        if let result = try Self.matchUnsignedIntegerJSONObject(value) {
            self = result
            return
        }
        if let result = Self.matchFloatingPointJSONObject(value) {
            self = result
            return
        }
        if let result = try Self.matchContainerJSONObject(value) {
            self = result
            return
        }

        throw JSONValueError.invalidJSONObject
    }

    public func encode(to encoder: Encoder) throws {
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

    public var stringValue: String? {
        guard case .string(let value) = self else {
            return nil
        }
        return value
    }

    public var boolValue: Bool? {
        guard case .bool(let value) = self else {
            return nil
        }
        return value
    }

    public var intValue: Int? {
        switch self {
        case .integer(let value):
            return value
        case .unsignedInteger(let value):
            return Int(exactly: value)
        default:
            return nil
        }
    }

    public var doubleValue: Double? {
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

    public var arrayValue: JSONArray? {
        guard case .array(let value) = self else {
            return nil
        }
        return value
    }

    public var dictionaryValue: JSONDictionary? {
        guard case .object(let value) = self else {
            return nil
        }
        return value
    }

    public var value: Any {
        jsonObject
    }

    var jsonObject: Any {
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
        case .array(let values):
            return values.map(\.jsonObject)
        case .object(let values):
            return values.mapValues(\.jsonObject)
        }
    }

    public func decoded<T: Decodable>(
        _ type: T.Type = T.self,
        using decoder: JSONDecoder = MCPJSONCoding.makeDecoder()
    ) throws -> T {
        let data = try MCPJSONCoding.makeWireEncoder().encode(self)
        return try decoder.decode(T.self, from: data)
    }

    package func decodeDynamically(
        _ type: any Decodable.Type,
        using decoder: JSONDecoder = MCPJSONCoding.makeDecoder()
    ) throws -> any Decodable {
        let data = try MCPJSONCoding.makeWireEncoder().encode(self)
        return try decoder.decode(type, from: data)
    }
}

extension JSONValue: CustomStringConvertible {
    public var description: String {
        switch self {
        case .null:
            return "null"
        case .string(let value):
            return value
        default:
            return String(describing: jsonObject)
        }
    }
}

extension JSONValue: CustomDebugStringConvertible {
    public var debugDescription: String {
        "JSONValue(\(description))"
    }
}

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        self = .null
    }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .integer(value)
    }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .double(value)
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) {
        self = .array(elements)
    }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(uniqueKeysWithValues: elements))
    }
}

public extension Dictionary where Key == String, Value == JSONValue {
    init<T: Encodable>(encoding value: T, using encoder: JSONEncoder = MCPJSONCoding.makeValueEncoder()) throws {
        let jsonValue = try JSONValue(encoding: value, using: encoder)
        guard case .object(let object) = jsonValue else {
            throw JSONValueError.expectedObject
        }
        self = object
    }

    init(encoding value: any Encodable, using encoder: JSONEncoder = MCPJSONCoding.makeValueEncoder()) throws {
        let jsonValue = try JSONValue(encoding: value, using: encoder)
        guard case .object(let object) = jsonValue else {
            throw JSONValueError.expectedObject
        }
        self = object
    }

    func decoded<T: Decodable>(
        _ type: T.Type = T.self,
        using decoder: JSONDecoder = MCPJSONCoding.makeDecoder()
    ) throws -> T {
        try JSONValue.object(self).decoded(type, using: decoder)
    }
}

public extension Array where Element == JSONValue {
    func decoded<T: Decodable>(
        _ type: T.Type = T.self,
        using decoder: JSONDecoder = MCPJSONCoding.makeDecoder()
    ) throws -> T {
        try JSONValue.array(self).decoded(type, using: decoder)
    }
}

// Leading underscore marks this as an internal, unstable type-erasing wrapper.
// swiftlint:disable:next type_name
struct _JSONValueOpaqueEncodable: Encodable {
    private let encodeImpl: (Encoder) throws -> Void

    init(_ value: any Encodable) {
        encodeImpl = value.encode(to:)
    }

    func encode(to encoder: Encoder) throws {
        try encodeImpl(encoder)
    }
}
