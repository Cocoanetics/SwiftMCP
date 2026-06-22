import Foundation

// swiftlint:disable force_cast
// File-wide: force casts here are generic type-dispatch (each `as! T` is preceded
// by a `T.self == X.self` guard, making the cast provably safe).

// MARK: - String to Decodable Conversion
extension String {
    func decode<T: Decodable>(_ type: T.Type, using decoder: JSONDecoder = MCPJSONCoding.makeDecoder()) throws -> T {
        guard let data = self.data(using: .utf8) else {
            throw MCPToolError.invalidArgumentType(
                parameterName: "jsonString",
                expectedType: "Valid JSON string",
                actualType: "Invalid JSON string"
            )
        }
        return try decoder.decode(type, from: data)
    }

    func decode(
        _ type: any Decodable.Type,
        using decoder: JSONDecoder = MCPJSONCoding.makeDecoder()
    ) throws -> any Decodable {
        guard let data = self.data(using: .utf8) else {
            throw MCPToolError.invalidArgumentType(
                parameterName: "jsonString",
                expectedType: "Valid JSON string",
                actualType: "Invalid JSON string"
            )
        }
        return try decoder.decode(type, from: data)
    }
}

// MARK: - Parameter Extraction Extensions for JSON Dictionaries
public extension Dictionary where Key == String, Value == JSONValue {

    func extractParameter<T>(named name: String) throws -> T {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let value = try extractKnownPrimitive(named: name, as: T.self, from: jsonValue) {
            return value
        }

        if let value = try extractCaseIterable(named: name, as: T.self, from: jsonValue) {
            return value
        }

        if let value = extractDecodableDynamic(as: T.self, from: jsonValue) {
            return value
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: String(describing: T.self),
            actualValue: jsonValue
        )
    }

    /// Handles the fixed set of primitive types that `extractParameter` understands directly,
    /// returning `nil` when `T` is not one of those types.
    private func extractKnownPrimitive<T>(
        named name: String,
        as type: T.Type,
        from jsonValue: JSONValue
    ) throws -> T? {
        if T.self == JSONValue.self {
            return (jsonValue as! T)
        }
        if T.self == Bool.self {
            let value = try extractBool(named: name)
            return (value as! T)
        }
        if T.self == Date.self {
            let value = try extractDate(named: name)
            return (value as! T)
        }
        if T.self == URL.self {
            let value = try extractURL(named: name)
            return (value as! T)
        }
        if T.self == UUID.self {
            let value = try extractUUID(named: name)
            return (value as! T)
        }
        if T.self == Data.self {
            let value = try extractData(named: name)
            return (value as! T)
        }
        if T.self == String.self, let stringValue = jsonValue.stringValue {
            return (stringValue as! T)
        }
        return nil
    }

    /// Extracts a single `CaseIterable` enum value from the JSON value, if `T` is one.
    private func extractCaseIterable<T>(
        named name: String,
        as type: T.Type,
        from jsonValue: JSONValue
    ) throws -> T? {
        guard let caseType = T.self as? any CaseIterable.Type else {
            return nil
        }

        guard let string = jsonValue.stringValue else {
            throw invalidArgumentType(parameterName: name, expectedType: "String", actualValue: jsonValue)
        }

        let caseLabels = caseType.caseLabels
        guard let index = caseLabels.firstIndex(of: string) else {
            throw MCPToolError.invalidEnumValue(
                parameterName: name,
                expectedValues: caseLabels,
                actualValue: string
            )
        }
        guard let allCases = caseType.allCases as? [T] else {
            preconditionFailure()
        }
        return allCases[index]
    }

    /// Best-effort decode of a `Decodable` value, returning `nil` when `T` is not Decodable
    /// or neither the value nor a JSON-string form of it can be decoded.
    private func extractDecodableDynamic<T>(
        as type: T.Type,
        from jsonValue: JSONValue
    ) -> T? {
        guard let decodableType = T.self as? any Decodable.Type else {
            return nil
        }
        let decoder = MCPJSONCoding.makeDecoder()

        if let decoded = try? jsonValue.decodeDynamically(decodableType, using: decoder) as? T {
            return decoded
        }
        if let jsonString = jsonValue.stringValue,
           let decoded = try? jsonString.decode(decodableType, using: decoder) as? T {
            return decoded
        }
        return nil
    }

    func extractOptionalParameter<T>(named name: String) throws -> T? {
        guard self[name] != nil else {
            return nil
        }
        return try extractParameter(named: name) as T
    }

    func extractArray<T>(named name: String, elementType: T.Type) throws -> [T] {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        guard case let .array(values) = jsonValue else {
            if let decodableArrayType = [T].self as? any Decodable.Type,
               let jsonString = jsonValue.stringValue,
               let decoded = try? jsonString.decode(decodableArrayType) as? [T] {
                return decoded
            }

            throw invalidArgumentType(
                parameterName: name,
                expectedType: "Array of \(String(describing: T.self))",
                actualValue: jsonValue
            )
        }

        if let mapped = try mapCaseIterableArray(named: name, elementType: elementType, values: values) {
            return mapped
        }

        if let mapped = try mapDecodableArray(named: name, elementType: elementType, values: values) {
            return mapped
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: "Array of \(String(describing: T.self))",
            actualValue: jsonValue
        )
    }

    /// Maps each element to a `CaseIterable` enum value, returning `nil` if `T` is not `CaseIterable`.
    private func mapCaseIterableArray<T>(
        named name: String,
        elementType: T.Type,
        values: [JSONValue]
    ) throws -> [T]? {
        guard let caseIterableType = elementType as? any CaseIterable.Type else {
            return nil
        }
        return try values.map { element in
            guard let stringValue = element.stringValue else {
                throw invalidArgumentType(
                    parameterName: name,
                    expectedType: "Array of Strings",
                    actualValue: element
                )
            }

            let caseLabels = caseIterableType.caseLabels
            guard let index = caseLabels.firstIndex(of: stringValue) else {
                throw MCPToolError.invalidEnumValue(
                    parameterName: name,
                    expectedValues: caseLabels,
                    actualValue: stringValue
                )
            }
            guard let allCases = caseIterableType.allCases as? [T] else {
                preconditionFailure()
            }
            return allCases[index]
        }
    }

    /// Maps each element to a `Decodable` value, returning `nil` if `T` is not `Decodable`.
    private func mapDecodableArray<T>(
        named name: String,
        elementType: T.Type,
        values: [JSONValue]
    ) throws -> [T]? {
        guard let decodableType = elementType as? any Decodable.Type else {
            return nil
        }
        let decoder = MCPJSONCoding.makeDecoder()
        return try values.map { element in
            if let decoded = try? element.decodeDynamically(decodableType, using: decoder) as? T {
                return decoded
            }
            if let jsonString = element.stringValue,
               let decoded = try? jsonString.decode(decodableType, using: decoder) as? T {
                return decoded
            }

            throw invalidArgumentType(
                parameterName: name,
                expectedType: String(describing: T.self),
                actualValue: element
            )
        }
    }

    func extractOptionalArray<T>(named name: String, elementType: T.Type) throws -> [T]? {
        guard self[name] != nil else {
            return nil
        }
        return try extractArray(named: name, elementType: elementType)
    }
}

// MARK: - Shared error helpers (internal across Dictionary+ParameterExtraction files)

internal func invalidArgumentType(
    parameterName: String,
    expectedType: String,
    actualValue: JSONValue
) -> MCPToolError {
    MCPToolError.invalidArgumentType(
        parameterName: parameterName,
        expectedType: expectedType,
        actualType: jsonTypeDescription(actualValue)
    )
}

internal func jsonTypeDescription(_ value: JSONValue) -> String {
    switch value {
    case .null:
        return "Null"
    case .bool:
        return "Bool"
    case .integer:
        return "Int"
    case .unsignedInteger:
        return "UInt"
    case .double:
        return "Double"
    case .string:
        return "String"
    case .array:
        return "Array"
    case .object:
        return "Object"
    }
}
// swiftlint:enable force_cast
