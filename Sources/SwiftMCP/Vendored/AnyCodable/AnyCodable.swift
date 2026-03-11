import Foundation

/**
 A type-erased `Codable` value backed by a checked-Sendable JSON value tree.

 `AnyCodable` preserves mixed JSON-compatible content while storing it in a
 fully checked-Sendable representation. Custom `Encodable` values are eagerly
 converted into their JSON representation when wrapped.
 */
@frozen public struct AnyCodable: Codable, Sendable {
    @usableFromInline
    let storage: _AnyCodableValue

    public init<T>(_ value: T?) {
        storage = _AnyCodableValue.make(from: value)
    }

    public init(from decoder: Decoder) throws {
        storage = try _AnyCodableValue(from: decoder)
    }

    public func encode(to encoder: Encoder) throws {
        try storage.encode(to: encoder)
    }

    public var value: Any { storage.value }
    public var sendableValue: any Sendable { storage.sendableValue }
    public var arrayValue: [Any]? { storage.arrayValue }
    public var dictionaryValue: [String: Any]? { storage.dictionaryValue }
    public var sendableDictionaryValue: [String: any Sendable]? { storage.sendableDictionaryValue }
    public var stringValue: String? { storage.stringValue }
    public var boolValue: Bool? { storage.boolValue }
    public var intValue: Int? { storage.intValue }
    public var doubleValue: Double? { storage.doubleValue }

    public func decoded<T: Decodable>(_ type: T.Type = T.self, using decoder: JSONDecoder = JSONDecoder()) throws -> T {
        try storage.decoded(type, using: decoder)
    }
}

extension AnyCodable: Equatable, Hashable {}

extension AnyCodable: CustomStringConvertible {
    public var description: String { storage.description }
}

extension AnyCodable: CustomDebugStringConvertible {
    public var debugDescription: String { "AnyCodable(\(storage.debugDescription))" }
}

extension AnyCodable: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        storage = .null
    }
}

extension AnyCodable: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

extension AnyCodable: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}

extension AnyCodable: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.init(value)
    }
}

extension AnyCodable: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension AnyCodable: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Any...) {
        self.init(elements)
    }
}

extension AnyCodable: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Any)...) {
        self.init(Dictionary(uniqueKeysWithValues: elements))
    }
}
