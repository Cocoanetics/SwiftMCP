//
//  MCPParameterInfo+JSONSchema.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 18.03.25.
//

import Foundation
import AnyCodable

protocol ArraySchemaBridge {
    static var elementType: Any.Type { get }
}

extension Array: ArraySchemaBridge {
    static var elementType: Any.Type { Element.self }
}

extension MCPParameterInfo {

    public var schema: JSONSchema {
        let defaultValue = schemaDefaultValue()
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

private extension MCPParameterInfo {
    func schemaDefaultValue() -> AnyCodable? {
        guard let value = defaultValue else { return nil }

        if let anyCodable = value as? AnyCodable {
            return anyCodable
        }

        if let string = value as? String {
            return AnyCodable(string)
        }
        if let bool = value as? Bool {
            return AnyCodable(bool)
        }
        if let int = value as? Int {
            return AnyCodable(int)
        }
        if let int64 = value as? Int64 {
            return AnyCodable(int64)
        }
        if let uint = value as? UInt {
            return AnyCodable(uint)
        }
        if let double = value as? Double {
            return AnyCodable(double)
        }
        if let float = value as? Float {
            return AnyCodable(float)
        }
        if let decimal = value as? Decimal {
            return AnyCodable(NSDecimalNumber(decimal: decimal).doubleValue)
        }
        if let date = value as? Date {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone.current
            formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
            return AnyCodable(formatter.string(from: date))
        }
        if let url = value as? URL {
            return AnyCodable(url.absoluteString)
        }
        if let uuid = value as? UUID {
            return AnyCodable(uuid.uuidString)
        }
        if let data = value as? Data {
            return AnyCodable(data.base64EncodedString())
        }
        if let values = value as? [String] {
            return AnyCodable(values)
        }
        if let values = value as? [Int] {
            return AnyCodable(values)
        }
        if let values = value as? [Double] {
            return AnyCodable(values)
        }
        if let values = value as? [Bool] {
            return AnyCodable(values)
        }
        if let values = value as? [Date] {
            let formatter = ISO8601DateFormatter()
            formatter.timeZone = TimeZone.current
            formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
            return AnyCodable(values.map { formatter.string(from: $0) })
        }
        if let values = value as? [URL] {
            return AnyCodable(values.map(\.absoluteString))
        }
        if let values = value as? [UUID] {
            return AnyCodable(values.map(\.uuidString))
        }
        if let values = value as? [Data] {
            return AnyCodable(values.map { $0.base64EncodedString() })
        }
        if let value = value as? CustomStringConvertible {
            return AnyCodable(value.description)
        }

        return nil
    }
}
