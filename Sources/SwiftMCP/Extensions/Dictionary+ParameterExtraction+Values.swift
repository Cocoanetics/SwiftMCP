import Foundation

// swiftlint:disable force_cast
// Force casts here are generic type-dispatch (each `as! T` is preceded
// by a `T.self == X.self` guard, making the cast provably safe).

// MARK: - Generic Value Extraction (numeric-aware)
public extension Dictionary where Key == String, Value == JSONValue {

    func extractValue<T>(named name: String, as type: T.Type = T.self) throws -> T {
        if let intType = T.self as? any BinaryInteger.Type {
            return try (extractNumber(named: name, as: intType) as! T)
        }

        if let floatType = T.self as? any BinaryFloatingPoint.Type {
            return try (extractNumber(named: name, as: floatType) as! T)
        }

        return try extractParameter(named: name)
    }

    func extractValue<T>(named name: String, as type: T?.Type) throws -> T? {
        guard self[name] != nil else { return nil }
        return try extractValue(named: name, as: T.self)
    }

    func extractValue<Element>(named name: String, as type: [Element].Type) throws -> [Element] {
        if let intType = Element.self as? any BinaryInteger.Type {
            return try (extractNumberArray(named: name, as: intType) as! [Element])
        }

        if let floatType = Element.self as? any BinaryFloatingPoint.Type {
            return try (extractNumberArray(named: name, as: floatType) as! [Element])
        }

        return try extractArray(named: name, elementType: Element.self)
    }

    func extractValue<Element>(named name: String, as type: [Element]?.Type) throws -> [Element]? {
        guard self[name] != nil else { return nil }
        return try extractValue(named: name, as: [Element].self)
    }
}
// swiftlint:enable force_cast
