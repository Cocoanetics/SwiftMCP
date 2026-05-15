import Foundation

// MARK: - JSONSchema encoding
extension JSONSchema {
    fileprivate typealias CodingKeys = JSONSchemaCodingKeys

    /// Payload for `.string` schemas, grouped so the encoder helper stays within the
    /// `function_parameter_count` budget.
    private struct StringPayload {
        let title: String?
        let description: String?
        let format: String?
        let minLength: Int?
        let maxLength: Int?
        let defaultValue: JSONValue?
    }

    /// Payload for `.number` schemas.
    private struct NumberPayload {
        let title: String?
        let description: String?
        let minimum: Double?
        let maximum: Double?
        let defaultValue: JSONValue?
    }

    /// Payload for `.enum` schemas.
    private struct EnumPayload {
        let values: [String]
        let title: String?
        let description: String?
        let enumNames: [String]?
        let defaultValue: JSONValue?
    }

    /**
     Encodes this JSONSchema instance into the given encoder.

     - Parameter encoder: The encoder to write data to
     - Throws: EncodingError if the data cannot be encoded
     */
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .string(let title, let description, let format, let minLength, let maxLength, let defaultValue):
            try encodeString(
                StringPayload(
                    title: title, description: description, format: format,
                    minLength: minLength, maxLength: maxLength, defaultValue: defaultValue
                ),
                into: &container
            )
        case .number(let title, let description, let minimum, let maximum, let defaultValue):
            try encodeNumber(
                NumberPayload(
                    title: title, description: description, minimum: minimum,
                    maximum: maximum, defaultValue: defaultValue
                ),
                into: &container
            )
        case .boolean(let title, let description, let defaultValue):
            try encodeBoolean(title: title, description: description, defaultValue: defaultValue, into: &container)
        case .array(let items, let title, let description, let defaultValue):
            try encodeArray(
                items: items, title: title, description: description, defaultValue: defaultValue,
                into: &container
            )
        case .object(let object, let defaultValue):
            try encodeObject(object, defaultValue: defaultValue, into: &container)
        case .enum(let values, let title, let description, let enumNames, let defaultValue):
            try encodeEnum(
                EnumPayload(
                    values: values, title: title, description: description,
                    enumNames: enumNames, defaultValue: defaultValue
                ),
                into: &container
            )
        case .oneOf(let schemas, let title, let description):
            try encodeOneOf(schemas, title: title, description: description, into: &container)
        }
    }

    /// Encodes a `.boolean` payload.
    private func encodeBoolean(
        title: String?,
        description: String?,
        defaultValue: JSONValue?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode("boolean", forKey: .type)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(defaultValue, forKey: .default)
    }

    /// Encodes an `.array` payload.
    private func encodeArray(
        items: JSONSchema,
        title: String?,
        description: String?,
        defaultValue: JSONValue?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode("array", forKey: .type)
        try container.encode(items, forKey: .items)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(defaultValue, forKey: .default)
    }

    /// Encodes a `.string` payload (plain string schema).
    private func encodeString(
        _ payload: StringPayload,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode("string", forKey: .type)
        try container.encodeIfPresent(payload.title, forKey: .title)
        try container.encodeIfPresent(payload.description, forKey: .description)
        try container.encodeIfPresent(payload.format, forKey: .format)
        try container.encodeIfPresent(payload.minLength, forKey: .minLength)
        try container.encodeIfPresent(payload.maxLength, forKey: .maxLength)
        try container.encodeIfPresent(payload.defaultValue, forKey: .default)
    }

    /// Encodes a `.number` payload.
    private func encodeNumber(
        _ payload: NumberPayload,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode("number", forKey: .type)
        try container.encodeIfPresent(payload.title, forKey: .title)
        try container.encodeIfPresent(payload.description, forKey: .description)
        try container.encodeIfPresent(payload.minimum, forKey: .minimum)
        try container.encodeIfPresent(payload.maximum, forKey: .maximum)
        try container.encodeIfPresent(payload.defaultValue, forKey: .default)
    }

    /// Encodes an `.object` payload, including properties / required / additionalProperties.
    private func encodeObject(
        _ object: JSONSchema.Object,
        defaultValue: JSONValue?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode("object", forKey: .type)

        if !object.properties.isEmpty {
            var propertiesContainer = container.nestedContainer(keyedBy: AnyCodingKey.self, forKey: .properties)
            for (key, value) in object.properties {
                try propertiesContainer.encode(value, forKey: AnyCodingKey(stringValue: key)!)
            }
        }

        if !object.required.isEmpty {
            try container.encode(object.required, forKey: .required)
        }

        try container.encodeIfPresent(object.title, forKey: .title)
        try container.encodeIfPresent(object.description, forKey: .description)
        try container.encodeIfPresent(object.additionalProperties, forKey: .additionalProperties)
        try container.encodeIfPresent(defaultValue, forKey: .default)
    }

    /// Encodes an `.enum` payload (string with enum values).
    private func encodeEnum(
        _ payload: EnumPayload,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        try container.encode("string", forKey: .type)
        try container.encodeIfPresent(payload.title, forKey: .title)
        try container.encodeIfPresent(payload.description, forKey: .description)
        try container.encode(payload.values, forKey: .enumValues)
        try container.encodeIfPresent(payload.enumNames, forKey: .enumNames)
        try container.encodeIfPresent(payload.defaultValue, forKey: .default)
    }

    /// Encodes a `.oneOf` payload, marking the `type` as `"object"` when all branches are objects.
    private func encodeOneOf(
        _ schemas: [JSONSchema],
        title: String?,
        description: String?,
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        if schemas.allSatisfy({
            if case .object = $0 { return true }
            return false
        }) {
            try container.encode("object", forKey: .type)
        }
        try container.encode(schemas, forKey: .oneOf)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
    }
}
