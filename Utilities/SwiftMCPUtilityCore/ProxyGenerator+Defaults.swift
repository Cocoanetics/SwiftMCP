import Foundation
import SwiftMCP

extension ProxyGenerator {
    static func defaultValueLiteral(for schema: JSONSchema, typeInfo: SwiftTypeInfo) -> String? {
        guard let defaultValue = schemaDefaultValue(schema) else { return nil }
        if defaultValue == .null {
            return "nil"
        }

        if typeInfo.needsEncoding, let stringValue = defaultValue.stringValue {
            return encodedLiteral(for: typeInfo.typeName, value: stringValue)
        }

        return swiftLiteral(from: defaultValue)
    }

    static func promptDefaultValueLiteral(
        for value: Sendable?,
        typeInfo: SwiftTypeInfo
    ) -> String? {
        guard let value else {
            return nil
        }

        if value is Void {
            return "nil"
        }

        if typeInfo.needsEncoding, let literal = encodedPromptDefaultLiteral(for: value, typeInfo: typeInfo) {
            return literal
        }

        guard let jsonValue = promptDefaultJSONValue(from: value) else {
            return nil
        }

        return swiftLiteral(from: jsonValue)
    }

    private static func encodedPromptDefaultLiteral(
        for value: Sendable,
        typeInfo: SwiftTypeInfo
    ) -> String? {
        switch value {
        case let date as Date:
            return encodedLiteral(for: typeInfo.typeName, value: MCPToolArgumentEncoder.encode(date))
        case let url as URL:
            return encodedLiteral(for: typeInfo.typeName, value: url.absoluteString)
        case let uuid as UUID:
            return encodedLiteral(for: typeInfo.typeName, value: uuid.uuidString)
        case let data as Data:
            return encodedLiteral(for: typeInfo.typeName, value: data.base64EncodedString())
        default:
            return nil
        }
    }

    static func schemaDefaultValue(_ schema: JSONSchema) -> JSONValue? {
        switch schema {
        case .string(_, _, _, _, _, let defaultValue):
            return defaultValue
        case .number(_, _, _, _, let defaultValue):
            return defaultValue
        case .boolean(_, _, let defaultValue):
            return defaultValue
        case .array(_, _, _, let defaultValue):
            return defaultValue
        case .object(_, let defaultValue):
            return defaultValue
        case .enum(_, _, _, _, let defaultValue):
            return defaultValue
        case .oneOf:
            return nil
        }
    }

    static func encodedLiteral(for typeName: String, value: String) -> String? {
        let escaped = escapeSwiftString(value)
        switch typeName {
        case "Date":
            return "ISO8601DateFormatter().date(from: \"\(escaped)\")!"
        case "URL":
            return "URL(string: \"\(escaped)\")!"
        case "UUID":
            return "UUID(uuidString: \"\(escaped)\")!"
        case "Data":
            return "Data(base64Encoded: \"\(escaped)\")!"
        default:
            return nil
        }
    }

    static func swiftLiteral(from value: JSONValue) -> String? {
        switch value {
        case .null:
            return "nil"
        case .string(let stringValue):
            return "\"\(escapeSwiftString(stringValue))\""
        case .bool(let boolValue):
            return boolValue ? "true" : "false"
        case .integer(let intValue):
            return "\(intValue)"
        case .unsignedInteger(let intValue):
            return "\(intValue)"
        case .double(let doubleValue):
            return String(describing: doubleValue)
        case .array(let arrayValue):
            return swiftLiteralForArray(arrayValue)
        case .object(let dictValue):
            return swiftLiteralForObject(dictValue)
        }
    }

    private static func swiftLiteralForArray(_ arrayValue: [JSONValue]) -> String? {
        var elements: [String] = []
        for element in arrayValue {
            guard let literal = swiftLiteral(from: element) else { return nil }
            elements.append(literal)
        }
        return "[\(elements.joined(separator: ", "))]"
    }

    private static func swiftLiteralForObject(_ dictValue: [String: JSONValue]) -> String? {
        var pairs: [String] = []
        for (key, value) in dictValue {
            guard let literal = swiftLiteral(from: value) else { return nil }
            pairs.append("\"\(escapeSwiftString(key))\": \(literal)")
        }
        return "[\(pairs.joined(separator: ", "))]"
    }

    static func promptDefaultJSONValue(from value: any Sendable) -> JSONValue? {
        if let scalar = promptDefaultScalarJSONValue(from: value) {
            return scalar
        }
        if let array = promptDefaultArrayJSONValue(from: value) {
            return array
        }
        return nil
    }

    private static func promptDefaultScalarJSONValue(from value: any Sendable) -> JSONValue? {
        if let jsonValue = value as? JSONValue {
            return jsonValue
        }
        if let stringValue = value as? String {
            return .string(stringValue)
        }
        if let boolValue = value as? Bool {
            return .bool(boolValue)
        }
        if let intValue = value as? Int {
            return .integer(intValue)
        }
        if let intValue = value as? Int64, let exact = Int(exactly: intValue) {
            return .integer(exact)
        }
        if let uintValue = value as? UInt {
            return .unsignedInteger(uintValue)
        }
        if let doubleValue = value as? Double {
            return .double(doubleValue)
        }
        if let floatValue = value as? Float {
            return .double(Double(floatValue))
        }
        return nil
    }

    private static func promptDefaultArrayJSONValue(from value: any Sendable) -> JSONValue? {
        if let values = value as? [String] {
            return .array(values.map(JSONValue.string))
        }
        if let values = value as? [Int] {
            return .array(values.map(JSONValue.integer))
        }
        if let values = value as? [Double] {
            return .array(values.map(JSONValue.double))
        }
        if let values = value as? [Bool] {
            return .array(values.map(JSONValue.bool))
        }
        return nil
    }
}
