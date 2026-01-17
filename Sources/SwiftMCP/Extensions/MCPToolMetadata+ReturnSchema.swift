import Foundation

struct MCPReturnSchemaInfo: Sendable {
    let schema: JSONSchema
    let description: String
}

extension MCPToolMetadata {
    private static let outputArrayWrapperKey = "items"

    private var shouldWrapOutputArray: Bool {
        guard let returnType else { return false }

        if returnType is [MCPText].Type
            || returnType is [MCPImage].Type
            || returnType is [MCPAudio].Type
            || returnType is [MCPResourceLink].Type
            || returnType is [MCPEmbeddedResource].Type
            || returnType is [any MCPResourceContent].Type {
            return false
        }

        guard case .array(let items, _, _, _) = returnSchemaInfo.schema else { return false }
        switch items {
        case .object, .oneOf:
            return true
        default:
            return false
        }
    }

    func wrapOutputIfNeeded(_ result: Encodable & Sendable) -> Encodable & Sendable {
        guard shouldWrapOutputArray else { return result }
        return MCPArrayOutputWrapper(items: AnyEncodable(result))
    }

    var returnSchemaInfo: MCPReturnSchemaInfo {
        let voidDescription = "Empty string (void function)"

        if returnType == nil || returnType == Void.self {
            return MCPReturnSchemaInfo(
                schema: .string(title: nil, description: voidDescription),
                description: returnTypeDescription ?? "A void function that performs an action"
            )
        }

        let returnType = returnType!

        if returnType is any MCPResourceContent.Type {
            let schema = MCPEmbeddedResource.jsonSchema(description: returnTypeDescription)
            return MCPReturnSchemaInfo(
                schema: schema,
                description: returnTypeDescription ?? "Embedded resource content"
            )
        }
        if returnType is [any MCPResourceContent].Type {
            let itemSchema = MCPEmbeddedResource.jsonSchema(description: returnTypeDescription)
            return MCPReturnSchemaInfo(
                schema: .array(items: itemSchema, title: nil, description: returnTypeDescription, defaultValue: nil),
                description: returnTypeDescription ?? "Array of embedded resources"
            )
        }
        if let schemaType = returnType as? any SchemaRepresentable.Type {
            return MCPReturnSchemaInfo(
                schema: schemaType.schemaMetadata.schema,
                description: returnTypeDescription ?? "A structured response"
            )
        }
        if let jsonSchemaType = returnType as? any JSONSchemaTypeConvertible.Type {
            return MCPReturnSchemaInfo(
                schema: jsonSchemaType.jsonSchema(description: returnTypeDescription),
                description: returnTypeDescription ?? "A structured response"
            )
        }
        if let caseIterableType = returnType as? any CaseIterable.Type {
            return MCPReturnSchemaInfo(
                schema: .enum(values: caseIterableType.caseLabels, description: returnTypeDescription),
                description: returnTypeDescription ?? "An enumerated value"
            )
        }
        if let arrayType = returnType as? any ArrayWithSchemaRepresentableElements.Type {
            return MCPReturnSchemaInfo(
                schema: arrayType.schema(description: returnTypeDescription),
                description: returnTypeDescription ?? "An array of structured responses"
            )
        }
        if let arrayType = returnType as? any ArrayWithCaseIterableElements.Type {
            return MCPReturnSchemaInfo(
                schema: arrayType.schema(description: returnTypeDescription),
                description: returnTypeDescription ?? "An array of enumerated values"
            )
        }
        if let arrayBridge = returnType as? ArraySchemaBridge.Type {
            let elementType = arrayBridge.elementType

            let itemSchema: JSONSchema
            if let jsonSchemaType = elementType as? any JSONSchemaTypeConvertible.Type {
                itemSchema = jsonSchemaType.jsonSchema(description: nil)
            } else if let schemaType = elementType as? any SchemaRepresentable.Type {
                itemSchema = schemaType.schemaMetadata.schema
            } else if let caseIterableType = elementType as? any CaseIterable.Type {
                itemSchema = .enum(values: caseIterableType.caseLabels)
            } else {
                itemSchema = .string(title: nil, description: nil, format: nil, minLength: nil, maxLength: nil)
            }

            return MCPReturnSchemaInfo(
                schema: .array(items: itemSchema, description: returnTypeDescription),
                description: returnTypeDescription ?? "An array of values"
            )
        }

        let schema: JSONSchema
        switch returnType {
        case is Int.Type, is Double.Type:
            schema = .number(title: nil, description: returnTypeDescription, minimum: nil, maximum: nil)
        case is Bool.Type:
            schema = .boolean(title: nil, description: returnTypeDescription, defaultValue: nil)
        case is Array<Any>.Type:
            if let elementType = (returnType as? Array<Any>.Type)?.elementType {
                let itemSchema: JSONSchema
                switch elementType {
                case let jsonSchemaType as any JSONSchemaTypeConvertible.Type:
                    itemSchema = jsonSchemaType.jsonSchema(description: nil)
                case is Int.Type, is Double.Type:
                    itemSchema = .number(title: nil, description: nil, minimum: nil, maximum: nil)
                case is Bool.Type:
                    itemSchema = .boolean(title: nil, description: nil, defaultValue: nil)
                default:
                    itemSchema = .string(title: nil, description: nil, format: nil, minLength: nil, maxLength: nil)
                }
                schema = .array(items: itemSchema, description: returnTypeDescription)
            } else {
                schema = .array(
                    items: .string(title: nil, description: nil, format: nil, minLength: nil, maxLength: nil),
                    description: returnTypeDescription
                )
            }
        default:
            schema = .string(
                title: nil,
                description: returnTypeDescription,
                format: nil,
                minLength: nil,
                maxLength: nil
            )
        }

        return MCPReturnSchemaInfo(
            schema: schema,
            description: returnTypeDescription ?? "The returned value of the tool"
        )
    }

    var outputSchema: JSONSchema? {
        let schema = returnSchemaInfo.schema.withoutRequired
        switch schema {
        case .object, .oneOf:
            return schema
        case .array:
            guard shouldWrapOutputArray else { return nil }
            let wrapper = JSONSchema.Object(
                properties: [Self.outputArrayWrapperKey: schema],
                required: [],
                title: nil,
                description: returnTypeDescription ?? returnSchemaInfo.description,
                additionalProperties: false
            )
            return .object(wrapper)
        default:
            return nil
        }
    }
}

private struct AnyEncodable: Encodable, @unchecked Sendable {
    let value: Encodable

    init(_ value: Encodable) {
        self.value = value
    }

    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

private struct MCPArrayOutputWrapper: Encodable, Sendable {
    let items: AnyEncodable
}
