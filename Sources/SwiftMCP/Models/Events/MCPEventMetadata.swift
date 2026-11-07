//
//  MCPEventMetadata.swift
//  SwiftMCP
//
//  Declaration-side metadata of an `@MCPEvent`, converted to the wire
//  `EventDescriptor` for `events/list`.
//

import Foundation

/// Metadata of one event type declared with `@MCPEvent`.
///
/// The annotated function's parameters describe the subscriber filter
/// (`inputSchema`) and its return type the delivered payload (`payloadSchema`).
public struct MCPEventMetadata: Sendable {
    public let functionMetadata: MCPFunctionMetadata

    /// Supported delivery modes (`"poll"`, `"push"`, `"webhook"`), if restricted.
    public let delivery: [String]?

    public init(
        name: String,
        description: String? = nil,
        parameters: [MCPParameterInfo],
        returnType: Sendable.Type? = nil,
        returnTypeDescription: String? = nil,
        isAsync: Bool = false,
        isThrowing: Bool = false,
        delivery: [String]? = nil
    ) {
        self.functionMetadata = MCPFunctionMetadata(
            name: name,
            description: description,
            parameters: parameters,
            returnType: returnType,
            returnTypeDescription: returnTypeDescription,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
        self.delivery = delivery
    }

    public var name: String { functionMetadata.name }
    public var description: String? { functionMetadata.description }
    public var parameters: [MCPParameterInfo] { functionMetadata.parameters }
    public var returnType: Sendable.Type? { functionMetadata.returnType }

    /// The wire descriptor listed by `events/list`.
    public var descriptor: EventDescriptor {
        let properties = Dictionary(uniqueKeysWithValues: parameters.map { ($0.name, $0.schema) })
        let required = Set(parameters.filter { $0.isRequired }.map { $0.name })
        let inputSchema = JSONSchema.object(JSONSchema.Object(
            properties: properties,
            required: required,
            additionalProperties: properties.isEmpty ? false : nil
        ))

        // Any payload type is valid (scalars and arrays included), so use the
        // general return schema rather than the restricted tool output schema.
        var payloadSchema: JSONSchema?
        if let returnType, returnType != Void.self {
            payloadSchema = MCPToolMetadata(
                name: name,
                parameters: [],
                returnType: returnType,
                returnTypeDescription: functionMetadata.returnTypeDescription
            ).returnSchemaInfo.schema.withoutRequired
        }

        return EventDescriptor(
            name: name,
            description: description,
            inputSchema: inputSchema,
            payloadSchema: payloadSchema,
            delivery: delivery
        )
    }
}
