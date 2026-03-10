import Foundation

/**
 A type-erased `Encodable` value backed by a checked-Sendable JSON value tree.
 */
@frozen public struct AnyEncodable: Encodable, Sendable {
    @usableFromInline
    let storage: _AnyCodableValue

    public init<T>(_ value: T?) {
        storage = _AnyCodableValue.make(from: value)
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

extension AnyEncodable: Equatable, Hashable {}

extension AnyEncodable: CustomStringConvertible {
    public var description: String { storage.description }
}

extension AnyEncodable: CustomDebugStringConvertible {
    public var debugDescription: String { "AnyEncodable(\(storage.debugDescription))" }
}

extension AnyEncodable: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) {
        storage = .null
    }
}

extension AnyEncodable: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self.init(value)
    }
}

extension AnyEncodable: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self.init(value)
    }
}

extension AnyEncodable: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self.init(value)
    }
}

extension AnyEncodable: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(value)
    }
}

extension AnyEncodable: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: Any...) {
        self.init(elements)
    }
}

extension AnyEncodable: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, Any)...) {
        self.init(Dictionary(uniqueKeysWithValues: elements))
    }
}
