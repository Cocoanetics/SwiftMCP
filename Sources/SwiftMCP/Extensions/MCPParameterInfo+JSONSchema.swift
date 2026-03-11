//
//  MCPParameterInfo+JSONSchema.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation

protocol ArraySchemaBridge {
    static var elementType: Any.Type { get }
}

extension Array: ArraySchemaBridge {
    static var elementType: Any.Type { Element.self }
}

extension MCPParameterInfo {

    public var schema: JSONSchema {
        let defaultValue = jsonDefaultValue()
        // If this is a JSONSchemaTypeConvertible type, use its schema
        if let convertibleType = type as? any JSONSchemaTypeConvertible.Type {
            return convertibleType.jsonSchema(description: description).applyingDefault(defaultValue)
        }

        // If this is a SchemaRepresentable type, use its schema
        if let schemaType = type as? any SchemaRepresentable.Type {
            return schemaType.schemaMetadata.schema.applyingDefault(defaultValue)
        }

        // If this is a CaseIterable type, return a string schema with enum values
        if let caseIterableType = type as? any CaseIterable.Type {
            return JSONSchema
                .enum(values: caseIterableType.caseLabels, description: description)
                .applyingDefault(defaultValue)
        }

        // Handle array types
        if let arrayType = type as? ArrayWithSchemaRepresentableElements.Type {

            return arrayType.schema(description: description).applyingDefault(defaultValue)
        }

        if let arrayType = type as? ArrayWithCaseIterableElements.Type {

            return arrayType.schema(description: description).applyingDefault(defaultValue)
        }

        if let arrayBridge = type as? ArraySchemaBridge.Type {
            // Get the element type from the array
            let type = arrayBridge.elementType

            let schema: JSONSchema

            if let convertibleType = type as? any JSONSchemaTypeConvertible.Type {
                schema = convertibleType.jsonSchema(description: nil)
            } else if let schemaType = type as? any SchemaRepresentable.Type {
                schema = schemaType.schemaMetadata.schema
            } else {
                schema = JSONSchema.string(title: nil, description: nil, format: nil, minLength: nil, maxLength: nil)
            }

            return JSONSchema.array(items: schema, description: description, defaultValue: defaultValue)
        }

        // Handle basic types
        switch type {
            case is Int.Type, is Double.Type:
                return JSONSchema.number(title: nil, description: description, minimum: nil, maximum: nil, defaultValue: defaultValue)
            case is Bool.Type:
                return JSONSchema.boolean(title: nil, description: description, defaultValue: defaultValue)
            default:
                return JSONSchema.string(title: nil, description: description, format: nil, minLength: nil, maxLength: nil, defaultValue: defaultValue)
        }
    }
}

extension MCPParameterInfo {
    func jsonDefaultValue() -> JSONValue? {
        guard let value = defaultValue else { return nil }

        if let jsonValue = value as? JSONValue {
            return jsonValue
        }

        if let string = value as? String {
            return .string(string)
        }
        if let bool = value as? Bool {
            return .bool(bool)
        }
        if let int = value as? Int {
            return .integer(int)
        }
        if let int64 = value as? Int64 {
            return Int(exactly: int64).map(JSONValue.integer)
        }
        if let uint = value as? UInt {
            return .unsignedInteger(uint)
        }
        if let double = value as? Double {
            return .double(double)
        }
        if let float = value as? Float {
            return .double(Double(float))
        }
        if let decimal = value as? Decimal {
            return .double(NSDecimalNumber(decimal: decimal).doubleValue)
        }
        if let date = value as? Date {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone.current
            formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
            return .string(formatter.string(from: date))
        }
        if let url = value as? URL {
            return .string(url.absoluteString)
        }
        if let uuid = value as? UUID {
            return .string(uuid.uuidString)
        }
        if let data = value as? Data {
            return .string(data.base64EncodedString())
        }
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
        if let values = value as? [Date] {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone.current
            formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
            return .array(values.map { .string(formatter.string(from: $0)) })
        }
        if let values = value as? [URL] {
            return .array(values.map { .string($0.absoluteString) })
        }
        if let values = value as? [UUID] {
            return .array(values.map { .string($0.uuidString) })
        }
        if let values = value as? [Data] {
            return .array(values.map { .string($0.base64EncodedString()) })
        }
        if Mirror(reflecting: value).displayStyle == .enum {
            return .string(String(describing: value))
        }
        if let value = value as? CustomStringConvertible {
            return .string(value.description)
        }

        return nil
    }
}
