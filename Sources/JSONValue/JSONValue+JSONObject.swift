import Foundation

// MARK: - JSONValue construction from `Any` JSON object trees
extension JSONValue {
    /// Matches `JSONValue`, `NSNull`, `Bool` and `String` instances.
    internal static func matchJSONValueOrNull(_ value: Any) -> JSONValue? {
        if value is NSNull {
            return .null
        }
        if let value = value as? JSONValue {
            return value
        }
        if let value = value as? Bool {
            return .bool(value)
        }
        if let value = value as? String {
            return .string(value)
        }
        return nil
    }

    /// Matches signed integer values (`Int`/`Int8`/`Int16`/`Int32`/`Int64`).
    internal static func matchIntegerJSONObject(_ value: Any) throws -> JSONValue? {
        if let value = value as? Int {
            return .integer(value)
        }
        if let value = value as? Int8 {
            return .integer(Int(value))
        }
        if let value = value as? Int16 {
            return .integer(Int(value))
        }
        if let value = value as? Int32 {
            return .integer(Int(value))
        }
        if let value = value as? Int64 {
            guard let exact = Int(exactly: value) else {
                throw JSONValueError.invalidJSONObject
            }
            return .integer(exact)
        }
        return nil
    }

    /// Matches unsigned integer values (`UInt`/`UInt8`/`UInt16`/`UInt32`/`UInt64`).
    internal static func matchUnsignedIntegerJSONObject(_ value: Any) throws -> JSONValue? {
        if let value = value as? UInt {
            return .unsignedInteger(value)
        }
        if let value = value as? UInt8 {
            return .unsignedInteger(UInt(value))
        }
        if let value = value as? UInt16 {
            return .unsignedInteger(UInt(value))
        }
        if let value = value as? UInt32 {
            return .unsignedInteger(UInt(value))
        }
        if let value = value as? UInt64 {
            guard let exact = UInt(exactly: value) else {
                throw JSONValueError.invalidJSONObject
            }
            return .unsignedInteger(exact)
        }
        return nil
    }

    /// Matches `Float`, `Double`, and `NSNumber` (preserving integer form when round-trippable).
    internal static func matchFloatingPointJSONObject(_ value: Any) -> JSONValue? {
        if let value = value as? Float {
            return .double(Double(value))
        }
        if let value = value as? Double {
            return .double(value)
        }
        if let value = value as? NSNumber {
            if let exact = Int(exactly: value.int64Value), value.doubleValue == Double(exact) {
                return .integer(exact)
            }
            if let exact = UInt(exactly: value.uint64Value), value.doubleValue == Double(exact) {
                return .unsignedInteger(exact)
            }
            return .double(value.doubleValue)
        }
        return nil
    }

    /// Matches collection types (`[Any]` and `[String: Any]`) by recursing element-wise.
    internal static func matchContainerJSONObject(_ value: Any) throws -> JSONValue? {
        if let value = value as? [Any] {
            return .array(try value.map { try JSONValue(jsonObject: $0) })
        }
        if let value = value as? [String: Any] {
            return .object(try value.mapValues { try JSONValue(jsonObject: $0) })
        }
        return nil
    }
}
