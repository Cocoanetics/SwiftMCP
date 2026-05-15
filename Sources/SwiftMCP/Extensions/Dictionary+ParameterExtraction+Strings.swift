import Foundation

// swiftlint:disable force_cast
// Force casts here are generic type-dispatch (each `as! T` is preceded
// by a `T.self == X.self` guard, making the cast provably safe).

// MARK: - String-based parameter extraction for resources

extension Dictionary where Key == String, Value == String {

    public func extractValueFromString<T>(named name: String, as type: T.Type = T.self) throws -> T {
        guard let stringValue = self[name] else {
            throw MCPResourceError.missingParameter(name: name)
        }

        if let losslessType = T.self as? LosslessStringConvertible.Type {
            guard let value = losslessType.init(stringValue) as? T else {
                throw MCPResourceError.typeMismatch(
                    parameter: name,
                    expectedType: String(describing: T.self),
                    actualValue: stringValue
                )
            }
            return value
        } else if T.self == String.self {
            return (stringValue as! T)
        } else if T.self == Date.self {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: stringValue) {
                return (date as! T)
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: stringValue) {
                return (date as! T)
            }
            throw MCPResourceError.typeMismatch(parameter: name, expectedType: "Date", actualValue: stringValue)
        } else if T.self == URL.self {
            guard let url = URL(string: stringValue) else {
                throw MCPResourceError.typeMismatch(parameter: name, expectedType: "URL", actualValue: stringValue)
            }
            return (url as! T)
        } else {
            throw MCPResourceError.typeMismatch(
                parameter: name,
                expectedType: String(describing: T.self),
                actualValue: stringValue
            )
        }
    }

    public func extractValueFromString<T>(
        named name: String,
        as type: T.Type = T.self,
        defaultValue: T
    ) throws -> T {
        if self[name] == nil {
            return defaultValue
        }
        return try extractValueFromString(named: name, as: type)
    }

    public func extractValueFromString<T>(named name: String, as type: T?.Type) throws -> T? {
        guard self[name] != nil else {
            return nil
        }
        return try extractValueFromString(named: name, as: T.self)
    }

    public func extractValueFromString<Element>(named name: String, as type: [Element].Type) throws -> [Element] {
        guard let stringValue = self[name] else {
            throw MCPResourceError.missingParameter(name: name)
        }

        if Element.self == String.self {
            let components = stringValue.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            return (components as! [Element])
        } else if Element.self == Int.self {
            let components = stringValue.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            return try (components.map { str in
                guard let value = Int(str) else {
                    throw MCPResourceError.typeMismatch(parameter: name, expectedType: "Int", actualValue: str)
                }
                return value
            } as! [Element])
        } else {
            throw MCPResourceError.typeMismatch(
                parameter: name,
                expectedType: String(describing: [Element].self),
                actualValue: stringValue
            )
        }
    }
}
// swiftlint:enable force_cast
