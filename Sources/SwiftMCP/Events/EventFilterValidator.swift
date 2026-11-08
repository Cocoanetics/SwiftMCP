//
//  EventFilterValidator.swift
//  SwiftMCP
//
//  Validates `events/subscribe` filter arguments against the event's declared
//  input schema, and emit payloads against its payload schema.
//

import Foundation

/// Why a subscriber filter does not conform to an event's `inputSchema`.
public struct EventFilterValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String
}

/// How undeclared object properties are treated when `additionalProperties` is omitted.
public enum EventSchemaAdditionalProperties: Sendable {
    /// Filters are closed sets: reject unknown members unless the schema sets
    /// `additionalProperties` to `true`.
    case closedUnlessAllowed
    /// Payloads follow JSON Schema's open-object default: allow unknown members
    /// unless the schema sets `additionalProperties` to `false`. A dictionary
    /// schema with no properties and a nil flag is therefore open.
    case openUnlessForbidden
}

/// Checks a value against the schema produced by ``MCPEventMetadata/descriptor``.
public enum EventFilterValidator {
    /// Throws ``EventFilterValidationError`` when `arguments` does not satisfy `schema`.
    public static func validate(
        _ arguments: JSONValue,
        against schema: JSONSchema?,
        additionalProperties: EventSchemaAdditionalProperties = .closedUnlessAllowed
    ) throws {
        guard let schema else { return }
        try check(arguments, schema, path: "arguments", additionalProperties: additionalProperties)
    }

    // swiftlint:disable:next cyclomatic_complexity
    private static func check(
        _ value: JSONValue,
        _ schema: JSONSchema,
        path: String,
        additionalProperties: EventSchemaAdditionalProperties
    ) throws {
        switch schema {
        case .object(let object, _):
            guard case .object(let dictionary) = value else { throw fail(path, "must be an object") }
            for name in object.required.sorted() where dictionary[name] == nil || dictionary[name] == .null {
                throw fail("\(path).\(name)", "is required")
            }
            for (name, member) in dictionary {
                if let propertySchema = object.properties[name] {
                    // An explicit null stands for an omitted optional property.
                    if member == .null && !object.required.contains(name) { continue }
                    try check(
                        member, propertySchema, path: "\(path).\(name)",
                        additionalProperties: additionalProperties
                    )
                } else if !allowsAdditionalProperties(object.additionalProperties, mode: additionalProperties) {
                    throw fail("\(path).\(name)", "is not a recognized property")
                }
            }
        case .string(_, _, _, let minLength, let maxLength, _):
            guard case .string(let string) = value else { throw fail(path, "must be a string") }
            if let minLength, string.count < minLength { throw fail(path, "is shorter than \(minLength)") }
            if let maxLength, string.count > maxLength { throw fail(path, "is longer than \(maxLength)") }
        case .number(_, _, let minimum, let maximum, _):
            let number: Double
            switch value {
            case .integer(let int): number = Double(int)
            case .unsignedInteger(let uint): number = Double(uint)
            case .double(let double): number = double
            default: throw fail(path, "must be a number")
            }
            if let minimum, number < minimum { throw fail(path, "is below \(minimum)") }
            if let maximum, number > maximum { throw fail(path, "is above \(maximum)") }
        case .boolean:
            guard case .bool = value else { throw fail(path, "must be a boolean") }
        case .array(let items, _, _, _):
            guard case .array(let elements) = value else { throw fail(path, "must be an array") }
            for (index, element) in elements.enumerated() {
                try check(
                    element, items, path: "\(path)[\(index)]", additionalProperties: additionalProperties
                )
            }
        case .enum(let values, _, _, _, _):
            guard case .string(let string) = value, values.contains(string) else {
                throw fail(path, "must be one of \(values.joined(separator: ", "))")
            }
        case .oneOf(let schemas, _, _):
            let matches = schemas.contains {
                (try? check(value, $0, path: path, additionalProperties: additionalProperties)) != nil
            }
            guard matches else { throw fail(path, "does not match any allowed shape") }
        }
    }

    private static func allowsAdditionalProperties(
        _ flag: Bool?, mode: EventSchemaAdditionalProperties
    ) -> Bool {
        switch mode {
        case .closedUnlessAllowed: return flag == true
        case .openUnlessForbidden: return flag != false
        }
    }

    private static func fail(_ path: String, _ reason: String) -> EventFilterValidationError {
        EventFilterValidationError(description: "\(path) \(reason)")
    }
}
