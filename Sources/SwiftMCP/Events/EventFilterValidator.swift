//
//  EventFilterValidator.swift
//  SwiftMCP
//
//  Validates `events/subscribe` filter arguments against the event's declared
//  input schema.
//

import Foundation

/// Why a subscriber filter does not conform to an event's `inputSchema`.
public struct EventFilterValidationError: Error, Equatable, Sendable, CustomStringConvertible {
    public let description: String
}

/// Checks a filter against the schema produced by ``MCPEventMetadata/descriptor``.
public enum EventFilterValidator {
    /// Throws ``EventFilterValidationError`` when `arguments` does not satisfy `schema`.
    public static func validate(_ arguments: JSONValue, against schema: JSONSchema?) throws {
        guard let schema else { return }
        try check(arguments, schema, path: "arguments")
    }

    // Filters are closed sets (the event's parameters), so unknown properties
    // are rejected unless the schema explicitly allows them.
    // swiftlint:disable:next cyclomatic_complexity
    private static func check(_ value: JSONValue, _ schema: JSONSchema, path: String) throws {
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
                    try check(member, propertySchema, path: "\(path).\(name)")
                } else if object.additionalProperties != true {
                    throw fail("\(path).\(name)", "is not a recognized filter property")
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
                try check(element, items, path: "\(path)[\(index)]")
            }
        case .enum(let values, _, _, _, _):
            guard case .string(let string) = value, values.contains(string) else {
                throw fail(path, "must be one of \(values.joined(separator: ", "))")
            }
        case .oneOf(let schemas, _, _):
            guard schemas.contains(where: { (try? check(value, $0, path: path)) != nil }) else {
                throw fail(path, "does not match any allowed shape")
            }
        }
    }

    private static func fail(_ path: String, _ reason: String) -> EventFilterValidationError {
        EventFilterValidationError(description: "\(path) \(reason)")
    }
}
