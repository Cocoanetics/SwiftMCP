import Foundation

/**
 A type-erased `Decodable` value backed by a checked-Sendable JSON value tree.
 */
@frozen public struct AnyDecodable: Decodable, Sendable {
    @usableFromInline
    let storage: _AnyCodableValue

    public init<T>(_ value: T?) {
        storage = _AnyCodableValue.make(from: value)
    }

    public init(from decoder: Decoder) throws {
        storage = try _AnyCodableValue(from: decoder)
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

extension AnyDecodable: Equatable, Hashable {}

extension AnyDecodable: CustomStringConvertible {
    public var description: String { storage.description }
}

extension AnyDecodable: CustomDebugStringConvertible {
    public var debugDescription: String { "AnyDecodable(\(storage.debugDescription))" }
}
