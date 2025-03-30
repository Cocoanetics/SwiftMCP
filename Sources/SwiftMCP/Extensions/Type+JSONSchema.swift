import Foundation

/// Protocol for types that can be converted to JSON Schema types
public protocol JSONSchemaTypeConvertible {
    /// The JSON Schema representation for this type
    static func jsonSchema(description: String?) -> JSONSchema
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
        .string(description: description)
    }
}

extension Character: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .string(description: description)
    }
}

extension Data: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .string(description: description)
    }
}

extension Array: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        let elementSchema: JSONSchema
        
        if let elementType = Element.self as? any JSONSchemaTypeConvertible.Type {
            elementSchema = elementType.jsonSchema(description: nil)
        } else if let schemaType = Element.self as? any SchemaRepresentable.Type {
            elementSchema = schemaType.schema
        } else if let caseIterableType = Element.self as? any CaseIterable.Type {
            elementSchema = .string(enumValues: caseIterableType.caseLabels)
        } else {
            elementSchema = .string()
        }
        
        return .array(items: elementSchema, description: description)
    }
}

extension Dictionary: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .object(properties: [:], required: [], description: description)
    }
}

extension Optional: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        if let wrappedType = Wrapped.self as? any JSONSchemaTypeConvertible.Type {
            return wrappedType.jsonSchema(description: description)
        } else if let schemaType = Wrapped.self as? any SchemaRepresentable.Type {
            return schemaType.schema
        } else if let caseIterableType = Wrapped.self as? any CaseIterable.Type {
            return .string(description: description, enumValues: caseIterableType.caseLabels)
        }
        return .string(description: description)
    }
} 