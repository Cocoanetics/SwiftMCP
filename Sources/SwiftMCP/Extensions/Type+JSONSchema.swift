import Foundation

/// Protocol for types that can be converted to JSON Schema types
public protocol JSONSchemaTypeConvertible {
    /// The JSON Schema representation for this type
    static func jsonSchema(description: String?) -> JSONSchema
}

// Add automatic conformance for CaseIterable types
extension CaseIterable {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .enum(values: caseLabels, description: description)
    }
}

extension Int: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension UInt: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension Int8: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension Int16: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension Int32: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension Int64: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension UInt8: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension UInt16: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension UInt32: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension UInt64: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension Float: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension Double: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .number(description: description)
    }
}

extension Bool: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .boolean(description: description)
    }
}

extension String: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .string(description: description, format: nil, minLength: nil, maxLength: nil)
    }
}

extension Character: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .string(description: description, format: nil, minLength: nil, maxLength: nil)
    }
}

extension Data: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .string(description: description, format: "byte", minLength: nil, maxLength: nil)
    }
}

extension Array: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        let elementSchema: JSONSchema

        if let elementType = Element.self as? any JSONSchemaTypeConvertible.Type {
            elementSchema = elementType.jsonSchema(description: nil)
        } else if let schemaType = Element.self as? any SchemaRepresentable.Type {
            elementSchema = schemaType.schemaMetadata.schema
        } else if let caseIterableType = Element.self as? any CaseIterable.Type {
            elementSchema = .enum(values: caseIterableType.caseLabels)
        } else {
            elementSchema = .string()
        }

        return .array(items: elementSchema, description: description)
    }
}

extension Dictionary: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .object(JSONSchema.Object(properties: [:], required: [], description: description))
    }
}

extension Optional: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        if let wrappedType = Wrapped.self as? any JSONSchemaTypeConvertible.Type {
            return wrappedType.jsonSchema(description: description)
        } else if let schemaType = Wrapped.self as? any SchemaRepresentable.Type {
            return schemaType.schemaMetadata.schema
        } else if let caseIterableType = Wrapped.self as? any CaseIterable.Type {
            return .enum(values: caseIterableType.caseLabels, description: description)
        }
        return .string(description: description)
    }
} 
