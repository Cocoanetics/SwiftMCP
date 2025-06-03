import Foundation
import AnyCodable

/// Encodes Encodable values into [String: AnyCodable] dictionaries.
public class DictionaryEncoder {
    public init() {}

    public func encode<T: Encodable>(_ value: T) throws -> [String: AnyCodable] {
        let encoder = _DictionaryEncoder()
        try value.encode(to: encoder)
        guard let dict = encoder.storage.topContainer as? [String: Any] else {
            throw EncodingError.invalidValue(value, EncodingError.Context(
                codingPath: [],
                debugDescription: "Top-level object did not encode as a dictionary."
            ))
        }
        // Convert [String: Any] to [String: AnyCodable]
        return dict.mapValues { AnyCodable($0) }
    }
}

// MARK: - _DictionaryEncoder

fileprivate class _DictionaryEncoder: Encoder {
    var storage: _DictionaryEncodingStorage = _DictionaryEncodingStorage()
    var codingPath: [CodingKey] = []
    var userInfo: [CodingUserInfoKey: Any] = [:]

    func container<Key>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        let container = DictionaryKeyedEncodingContainer<Key>(referencing: self)
        return KeyedEncodingContainer(container)
    }

    func unkeyedContainer() -> UnkeyedEncodingContainer {
        return DictionaryUnkeyedEncodingContainer(referencing: self)
    }

    func singleValueContainer() -> SingleValueEncodingContainer {
        return DictionarySingleValueEncodingContainer(referencing: self)
    }
}

// MARK: - Storage

fileprivate struct _DictionaryEncodingStorage {
    private(set) var containers: [Any] = []

    var topContainer: Any? { containers.last }

    mutating func pushKeyedContainer() -> NSMutableDictionary {
        let dictionary = NSMutableDictionary()
        containers.append(dictionary)
        return dictionary
    }

    mutating func pushUnkeyedContainer() -> NSMutableArray {
        let array = NSMutableArray()
        containers.append(array)
        return array
    }

    mutating func push(container: Any) {
        containers.append(container)
    }

    mutating func popContainer() -> Any {
        return containers.popLast()!
    }
}

// MARK: - KeyedEncodingContainer

fileprivate struct DictionaryKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
    typealias Key = K

    private let encoder: _DictionaryEncoder
    private let container: NSMutableDictionary

    init(referencing encoder: _DictionaryEncoder) {
        self.encoder = encoder
        self.container = encoder.storage.pushKeyedContainer()
    }

    var codingPath: [CodingKey] { encoder.codingPath }

    mutating func encodeNil(forKey key: K) { 
        // Do nothing - omit the key entirely
    }

    mutating func encode<T: Encodable>(_ value: T, forKey key: K) throws {
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        container[key.stringValue] = try _box(value, encoder: encoder)
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type, forKey key: K)
        -> KeyedEncodingContainer<NestedKey> {
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        let container = DictionaryKeyedEncodingContainer<NestedKey>(referencing: encoder)
        self.container[key.stringValue] = encoder.storage.topContainer!
        return KeyedEncodingContainer(container)
    }

    mutating func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        encoder.codingPath.append(key)
        defer { encoder.codingPath.removeLast() }
        let container = DictionaryUnkeyedEncodingContainer(referencing: encoder)
        self.container[key.stringValue] = encoder.storage.topContainer!
        return container
    }

    mutating func superEncoder() -> Encoder { encoder }
    mutating func superEncoder(forKey key: K) -> Encoder { encoder }
}

// MARK: - UnkeyedEncodingContainer

fileprivate struct DictionaryUnkeyedEncodingContainer: UnkeyedEncodingContainer {
    private let encoder: _DictionaryEncoder
    private let container: NSMutableArray

    init(referencing encoder: _DictionaryEncoder) {
        self.encoder = encoder
        self.container = encoder.storage.pushUnkeyedContainer()
    }

    var codingPath: [CodingKey] { encoder.codingPath }
    var count: Int { container.count }

    // For arrays, we keep NSNull to preserve structure and indices
    mutating func encodeNil() { container.add(NSNull()) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        container.add(try _box(value, encoder: encoder))
    }

    mutating func nestedContainer<NestedKey>(keyedBy keyType: NestedKey.Type)
        -> KeyedEncodingContainer<NestedKey> {
        let container = DictionaryKeyedEncodingContainer<NestedKey>(referencing: encoder)
        self.container.add(encoder.storage.topContainer!)
        return KeyedEncodingContainer(container)
    }

    mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
        let container = DictionaryUnkeyedEncodingContainer(referencing: encoder)
        self.container.add(encoder.storage.topContainer!)
        return container
    }

    mutating func superEncoder() -> Encoder { encoder }
}

// MARK: - SingleValueEncodingContainer

fileprivate struct DictionarySingleValueEncodingContainer: SingleValueEncodingContainer {
    private let encoder: _DictionaryEncoder

    init(referencing encoder: _DictionaryEncoder) {
        self.encoder = encoder
    }

    var codingPath: [CodingKey] { encoder.codingPath }

    // For single values, we encode NSNull (this represents the entire value being nil)
    mutating func encodeNil() { encoder.storage.push(container: NSNull()) }

    mutating func encode<T: Encodable>(_ value: T) throws {
        encoder.storage.push(container: try _box(value, encoder: encoder))
    }
}

// MARK: - Boxing

fileprivate func _box<T: Encodable>(_ value: T, encoder: _DictionaryEncoder) throws -> Any {
    if let date = value as? Date {
        return date.timeIntervalSince1970
    } else if let data = value as? Data {
        return data.base64EncodedString()
    } else if let url = value as? URL {
        return url.absoluteString
    } else if let decimal = value as? Decimal {
        return decimal.description
    } else if let number = value as? NSNumber {
        return number
    } else if let string = value as? String {
        return string
    } else if let bool = value as? Bool {
        return bool
    } else if let int = value as? Int {
        return int
    } else if let double = value as? Double {
        return double
    } else if let float = value as? Float {
        return float
    } else {
        let depthEncoder = _DictionaryEncoder()
        try value.encode(to: depthEncoder)
        return depthEncoder.storage.popContainer()
    }
} 