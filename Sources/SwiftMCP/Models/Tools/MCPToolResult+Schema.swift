import Foundation

extension MCPText: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .object(JSONSchema.Object(
            properties: [
                "type": .enum(values: ["text"], title: nil, description: nil, enumNames: nil, defaultValue: nil),
                "text": .string(title: nil, description: "Tool result text", format: nil, minLength: nil, maxLength: nil)
            ],
            required: ["type", "text"],
            description: description ?? "Text content"
        ))
    }
}

extension MCPImage: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .object(JSONSchema.Object(
            properties: [
                "type": .enum(values: ["image"], title: nil, description: nil, enumNames: nil, defaultValue: nil),
                "data": .string(title: nil, description: "Base64-encoded image data", format: "byte", minLength: nil, maxLength: nil),
                "mimeType": .string(title: nil, description: "Image MIME type", format: nil, minLength: nil, maxLength: nil),
                "annotations": annotationsSchema()
            ],
            required: ["type", "data", "mimeType"],
            description: description ?? "Image content"
        ))
    }
}

extension MCPAudio: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .object(JSONSchema.Object(
            properties: [
                "type": .enum(values: ["audio"], title: nil, description: nil, enumNames: nil, defaultValue: nil),
                "data": .string(title: nil, description: "Base64-encoded audio data", format: "byte", minLength: nil, maxLength: nil),
                "mimeType": .string(title: nil, description: "Audio MIME type", format: nil, minLength: nil, maxLength: nil),
                "annotations": annotationsSchema()
            ],
            required: ["type", "data", "mimeType"],
            description: description ?? "Audio content"
        ))
    }
}

extension MCPResourceLink: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        .object(JSONSchema.Object(
            properties: [
                "type": .enum(values: ["resource_link"], title: nil, description: nil, enumNames: nil, defaultValue: nil),
                "uri": .string(title: nil, description: "Resource URI", format: "uri", minLength: nil, maxLength: nil),
                "name": .string(title: nil, description: "Resource name", format: nil, minLength: nil, maxLength: nil),
                "description": .string(title: nil, description: "Resource description", format: nil, minLength: nil, maxLength: nil),
                "mimeType": .string(title: nil, description: "Resource MIME type", format: nil, minLength: nil, maxLength: nil),
                "annotations": annotationsSchema()
            ],
            required: ["type", "uri", "name"],
            description: description ?? "Resource link content"
        ))
    }
}

extension MCPEmbeddedResource: JSONSchemaTypeConvertible {
    public static func jsonSchema(description: String?) -> JSONSchema {
        let embeddedResource = JSONSchema.object(JSONSchema.Object(
            properties: [
                "uri": .string(title: nil, description: "Resource URI", format: "uri", minLength: nil, maxLength: nil),
                "mimeType": .string(title: nil, description: "Resource MIME type", format: nil, minLength: nil, maxLength: nil),
                "text": .string(title: nil, description: "Embedded resource text", format: nil, minLength: nil, maxLength: nil),
                "blob": .string(title: nil, description: "Base64-encoded resource data", format: "byte", minLength: nil, maxLength: nil),
                "annotations": annotationsSchema()
            ],
            required: ["uri"],
            description: "Embedded resource"
        ))

        return .object(JSONSchema.Object(
            properties: [
                "type": .enum(values: ["resource"], title: nil, description: nil, enumNames: nil, defaultValue: nil),
                "resource": embeddedResource
            ],
            required: ["type", "resource"],
            description: description ?? "Embedded resource content"
        ))
    }
}

private func annotationsSchema() -> JSONSchema {
    .object(JSONSchema.Object(
        properties: [
            "audience": .array(items: .string(title: nil, description: nil), title: nil, description: "Audience list", defaultValue: nil),
            "priority": .number(title: nil, description: "Priority (0.0-1.0)", minimum: nil, maximum: nil),
            "lastModified": .string(title: nil, description: "ISO 8601 timestamp", format: "date-time", minLength: nil, maxLength: nil)
        ],
        required: [],
        description: "Optional content annotations",
        additionalProperties: true
    ))
}
