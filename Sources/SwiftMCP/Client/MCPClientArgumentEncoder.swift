import Foundation

/// Helpers for encoding client arguments into MCP tool payloads.
public enum MCPClientArgumentEncoder {
    public static func encode<T: Encodable>(_ value: T) throws -> JSONValue {
        try JSONValue(encoding: value)
    }

    public static func encode(_ value: Date) throws -> JSONValue {
        .string(MCPToolArgumentEncoder.encode(value))
    }

    public static func encode(_ value: URL) throws -> JSONValue {
        .string(MCPToolArgumentEncoder.encode(value))
    }

    public static func encode(_ value: UUID) throws -> JSONValue {
        .string(MCPToolArgumentEncoder.encode(value))
    }

    public static func encode(_ value: Data) throws -> JSONValue {
        .string(MCPToolArgumentEncoder.encode(value))
    }

    public static func encode<T: CaseIterable>(_ value: T) throws -> JSONValue {
        .string(String(describing: value))
    }

    /// Tie-breaker for types conforming to both `Encodable` and `CaseIterable`.
    public static func encode<T: Encodable & CaseIterable>(_ value: T) throws -> JSONValue {
        try JSONValue(encoding: value)
    }

    public static func encode(_ values: [Date]) throws -> JSONValue {
        .array(MCPToolArgumentEncoder.encode(values).map(JSONValue.string))
    }

    public static func encode(_ values: [URL]) throws -> JSONValue {
        .array(MCPToolArgumentEncoder.encode(values).map(JSONValue.string))
    }

    public static func encode(_ values: [UUID]) throws -> JSONValue {
        .array(MCPToolArgumentEncoder.encode(values).map(JSONValue.string))
    }

    public static func encode(_ values: [Data]) throws -> JSONValue {
        .array(MCPToolArgumentEncoder.encode(values).map(JSONValue.string))
    }

    public static func encode<T: CaseIterable>(_ values: [T]) throws -> JSONValue {
        .array(values.map { .string(String(describing: $0)) })
    }

    /// Tie-breaker for arrays of types conforming to both `Encodable` and `CaseIterable`.
    public static func encode<T: Encodable & CaseIterable>(_ values: [T]) throws -> JSONValue {
        try JSONValue(encoding: values)
    }
}
