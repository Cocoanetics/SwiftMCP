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

    /// Proxy-aware encoding for `Data`: generates CID placeholder if uploads supported, falls back to base64.
    public static func encode(_ value: Data, proxy: MCPServerProxy) async throws -> JSONValue {
        if await proxy.supportsFileUpload {
            let cid = UUID().uuidString
            await proxy.registerPendingUpload(cid: cid, data: value)
            return .string("cid:\(cid)")
        }
        return .string(MCPToolArgumentEncoder.encode(value))
    }

    public static func encode<T: CaseIterable>(_ value: T) throws -> JSONValue {
        .string(String(describing: value))
    }

    /// Tie-breaker for types conforming to both `Encodable` and `CaseIterable`.
    /// Uses the case label (not the raw/Codable encoding) to stay consistent
    /// with MCP parameter decoding which validates against `caseLabels`.
    public static func encode<T: Encodable & CaseIterable>(_ value: T) throws -> JSONValue {
        .string(String(describing: value))
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

    /// Proxy-aware encoding for `[Data]`: generates CID placeholders if uploads supported, falls back to base64.
    public static func encode(_ values: [Data], proxy: MCPServerProxy) async throws -> JSONValue {
        if await proxy.supportsFileUpload {
            var results: [JSONValue] = []
            for value in values {
                let cid = UUID().uuidString
                await proxy.registerPendingUpload(cid: cid, data: value)
                results.append(.string("cid:\(cid)"))
            }
            return .array(results)
        }
        return .array(MCPToolArgumentEncoder.encode(values).map(JSONValue.string))
    }

    public static func encode<T: CaseIterable>(_ values: [T]) throws -> JSONValue {
        .array(values.map { .string(String(describing: $0)) })
    }

    /// Tie-breaker for arrays of types conforming to both `Encodable` and `CaseIterable`.
    /// Uses case labels to stay consistent with MCP parameter decoding.
    public static func encode<T: Encodable & CaseIterable>(_ values: [T]) throws -> JSONValue {
        .array(values.map { .string(String(describing: $0)) })
    }
}
