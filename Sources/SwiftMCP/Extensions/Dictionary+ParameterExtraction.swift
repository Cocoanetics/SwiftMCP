import Foundation

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

    func decode(_ type: any Decodable.Type, using decoder: JSONDecoder = MCPJSONCoding.makeDecoder()) throws -> any Decodable {
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

        if T.self == JSONValue.self {
            return jsonValue as! T
        }
        if T.self == Bool.self {
            return try extractBool(named: name) as! T
        }
        if T.self == Date.self {
            return try extractDate(named: name) as! T
        }
        if T.self == URL.self {
            return try extractURL(named: name) as! T
        }
        if T.self == UUID.self {
            return try extractUUID(named: name) as! T
        }
        if T.self == Data.self {
            return try extractData(named: name) as! T
        }
        if T.self == String.self, let stringValue = jsonValue.stringValue {
            return stringValue as! T
        }
        if let caseType = T.self as? any CaseIterable.Type {
            guard let string = jsonValue.stringValue else {
                throw invalidArgumentType(parameterName: name, expectedType: "String", actualValue: jsonValue)
            }

            let caseLabels = caseType.caseLabels
            guard let index = caseLabels.firstIndex(of: string) else {
                throw MCPToolError.invalidEnumValue(parameterName: name, expectedValues: caseLabels, actualValue: string)
            }
            guard let allCases = caseType.allCases as? [T] else {
                preconditionFailure()
            }
            return allCases[index]
        }
        if let decodableType = T.self as? any Decodable.Type {
            let decoder = MCPJSONCoding.makeDecoder()

            if let decoded = try? jsonValue.decodeDynamically(decodableType, using: decoder) as? T {
                return decoded
            }
            if let jsonString = jsonValue.stringValue,
               let decoded = try? jsonString.decode(decodableType, using: decoder) as? T {
                return decoded
            }
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: String(describing: T.self),
            actualValue: jsonValue
        )
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

        if let caseIterableType = elementType as? any CaseIterable.Type {
            return try values.map { element in
                guard let stringValue = element.stringValue else {
                    throw invalidArgumentType(parameterName: name, expectedType: "Array of Strings", actualValue: element)
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

        if let decodableType = elementType as? any Decodable.Type {
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

        throw invalidArgumentType(
            parameterName: name,
            expectedType: "Array of \(String(describing: T.self))",
            actualValue: jsonValue
        )
    }

    func extractOptionalArray<T>(named name: String, elementType: T.Type) throws -> [T]? {
        guard self[name] != nil else {
            return nil
        }
        return try extractArray(named: name, elementType: elementType)
    }

    func extractNumber<N: BinaryInteger>(named name: String, as type: N.Type = N.self) throws -> N {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let value = N.convert(from: jsonValue) {
            return value
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: String(describing: N.self),
            actualValue: jsonValue
        )
    }

    func extractNumber<N: BinaryFloatingPoint>(named name: String, as type: N.Type = N.self) throws -> N {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let value = N.convert(from: jsonValue) {
            return value
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: String(describing: N.self),
            actualValue: jsonValue
        )
    }

    func extractNumberArray<N: BinaryInteger>(named name: String, as type: N.Type = N.self) throws -> [N] {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        guard case let .array(values) = jsonValue else {
            throw invalidArgumentType(
                parameterName: name,
                expectedType: "Array of \(String(describing: N.self))",
                actualValue: jsonValue
            )
        }

        return try values.map { element in
            guard let converted = N.convert(from: element) else {
                throw invalidArgumentType(
                    parameterName: name,
                    expectedType: String(describing: N.self),
                    actualValue: element
                )
            }
            return converted
        }
    }

    func extractNumberArray<N: BinaryFloatingPoint>(named name: String, as type: N.Type = N.self) throws -> [N] {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }
        guard case let .array(values) = jsonValue else {
            throw invalidArgumentType(
                parameterName: name,
                expectedType: "Array of \(String(describing: N.self))",
                actualValue: jsonValue
            )
        }

        return try values.map { element in
            guard let converted = N.convert(from: element) else {
                throw invalidArgumentType(
                    parameterName: name,
                    expectedType: String(describing: N.self),
                    actualValue: element
                )
            }
            return converted
        }
    }

    func extractOptionalNumber<N: BinaryInteger>(named name: String, as type: N.Type = N.self) throws -> N? {
        guard self[name] != nil else { return nil }
        return try extractNumber(named: name, as: type)
    }

    func extractOptionalNumber<N: BinaryFloatingPoint>(named name: String, as type: N.Type = N.self) throws -> N? {
        guard self[name] != nil else { return nil }
        return try extractNumber(named: name, as: type)
    }

    func extractOptionalNumberArray<N: BinaryInteger>(named name: String, as type: N.Type = N.self) throws -> [N]? {
        guard self[name] != nil else { return nil }
        return try extractNumberArray(named: name, as: type)
    }

    func extractOptionalNumberArray<N: BinaryFloatingPoint>(named name: String, as type: N.Type = N.self) throws -> [N]? {
        guard self[name] != nil else { return nil }
        return try extractNumberArray(named: name, as: type)
    }

    func extractValue<T>(named name: String, as type: T.Type = T.self) throws -> T {
        if let intType = T.self as? any BinaryInteger.Type {
            return try extractNumber(named: name, as: intType) as! T
        }

        if let floatType = T.self as? any BinaryFloatingPoint.Type {
            return try extractNumber(named: name, as: floatType) as! T
        }

        return try extractParameter(named: name)
    }

    func extractValue<T>(named name: String, as type: T?.Type) throws -> T? {
        guard self[name] != nil else { return nil }
        return try extractValue(named: name, as: T.self)
    }

    func extractValue<Element>(named name: String, as type: [Element].Type) throws -> [Element] {
        if let intType = Element.self as? any BinaryInteger.Type {
            return try extractNumberArray(named: name, as: intType) as! [Element]
        }

        if let floatType = Element.self as? any BinaryFloatingPoint.Type {
            return try extractNumberArray(named: name, as: floatType) as! [Element]
        }

        return try extractArray(named: name, elementType: Element.self)
    }

    func extractValue<Element>(named name: String, as type: [Element]?.Type) throws -> [Element]? {
        guard self[name] != nil else { return nil }
        return try extractValue(named: name, as: [Element].self)
    }

    func extractInt(named name: String) throws -> Int {
        try extractNumber(named: name, as: Int.self)
    }

    func extractDouble(named name: String) throws -> Double {
        try extractNumber(named: name, as: Double.self)
    }

    func extractFloat(named name: String) throws -> Float {
        try extractNumber(named: name, as: Float.self)
    }

    func extractIntArray(named name: String) throws -> [Int] {
        try extractNumberArray(named: name, as: Int.self)
    }

    func extractDoubleArray(named name: String) throws -> [Double] {
        try extractNumberArray(named: name, as: Double.self)
    }

    func extractFloatArray(named name: String) throws -> [Float] {
        try extractNumberArray(named: name, as: Float.self)
    }

    func extractDate(named name: String) throws -> Date {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let stringValue = jsonValue.stringValue {
            let isoFormatter = ISO8601DateFormatter()
            if let date = isoFormatter.date(from: stringValue) {
                return date
            }
            if let timestampDouble = Double(stringValue) {
                return Date(timeIntervalSince1970: timestampDouble)
            }
        }

        if let timestampDouble = jsonValue.doubleValue {
            return Date(timeIntervalSince1970: timestampDouble)
        }

        throw invalidArgumentType(
            parameterName: name,
            expectedType: "ISO 8601 Date",
            actualValue: jsonValue
        )
    }

    func extractBool(named name: String) throws -> Bool {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let boolValue = jsonValue.boolValue {
            return boolValue
        }

        if let stringValue = jsonValue.stringValue {
            switch stringValue.lowercased() {
            case "true":
                return true
            case "false":
                return false
            default:
                throw invalidArgumentType(parameterName: name, expectedType: "Bool", actualValue: jsonValue)
            }
        }

        throw invalidArgumentType(parameterName: name, expectedType: "Bool", actualValue: jsonValue)
    }

    func extractURL(named name: String) throws -> URL {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let stringValue = jsonValue.stringValue,
           let url = URL(string: stringValue) {
            return url
        }

        throw invalidArgumentType(parameterName: name, expectedType: "URL", actualValue: jsonValue)
    }

    func extractUUID(named name: String) throws -> UUID {
        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let stringValue = jsonValue.stringValue,
           let uuid = UUID(uuidString: stringValue) {
            return uuid
        }

        throw invalidArgumentType(parameterName: name, expectedType: "UUID", actualValue: jsonValue)
    }

    func extractData(named name: String) throws -> Data {
        // Check for pre-resolved upload data (file-based uploads bypass base64)
        if let resolved = ResolvedUploads.current?[name] {
            return resolved
        }

        guard let jsonValue = self[name] else {
            preconditionFailure("Failed to retrieve value for parameter \(name)")
        }

        if let stringValue = jsonValue.stringValue,
           let data = Data(base64Encoded: stringValue) {
            return data
        }

        throw invalidArgumentType(parameterName: name, expectedType: "Base64-encoded Data", actualValue: jsonValue)
    }
}

// MARK: - String-based parameter extraction for resources

extension Dictionary where Key == String, Value == String {

    public func extractValueFromString<T>(named name: String, as type: T.Type = T.self) throws -> T {
        guard let stringValue = self[name] else {
            throw MCPResourceError.missingParameter(name: name)
        }

        if let losslessType = T.self as? LosslessStringConvertible.Type {
            guard let value = losslessType.init(stringValue) as? T else {
                throw MCPResourceError.typeMismatch(parameter: name, expectedType: String(describing: T.self), actualValue: stringValue)
            }
            return value
        } else if T.self == String.self {
            return stringValue as! T
        } else if T.self == Date.self {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: stringValue) {
                return date as! T
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: stringValue) {
                return date as! T
            }
            throw MCPResourceError.typeMismatch(parameter: name, expectedType: "Date", actualValue: stringValue)
        } else if T.self == URL.self {
            guard let url = URL(string: stringValue) else {
                throw MCPResourceError.typeMismatch(parameter: name, expectedType: "URL", actualValue: stringValue)
            }
            return url as! T
        } else {
            throw MCPResourceError.typeMismatch(parameter: name, expectedType: String(describing: T.self), actualValue: stringValue)
        }
    }

    public func extractValueFromString<T>(named name: String, as type: T.Type = T.self, defaultValue: T) throws -> T {
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
            return components as! [Element]
        } else if Element.self == Int.self {
            let components = stringValue.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
            return try components.map { str in
                guard let value = Int(str) else {
                    throw MCPResourceError.typeMismatch(parameter: name, expectedType: "Int", actualValue: str)
                }
                return value
            } as! [Element]
        } else {
            throw MCPResourceError.typeMismatch(parameter: name, expectedType: String(describing: [Element].self), actualValue: stringValue)
        }
    }
}

private func invalidArgumentType(parameterName: String, expectedType: String, actualValue: JSONValue) -> MCPToolError {
    MCPToolError.invalidArgumentType(
        parameterName: parameterName,
        expectedType: expectedType,
        actualType: jsonTypeDescription(actualValue)
    )
}

private func jsonTypeDescription(_ value: JSONValue) -> String {
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
