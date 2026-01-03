import Foundation

/// Helpers for encoding client arguments into MCP tool payloads.
public enum MCPClientArgumentEncoder {
    public static func encode<T>(_ value: T) -> T {
        value
    }

    public static func encode(_ value: Date) -> String {
        MCPToolArgumentEncoder.encode(value)
    }

    public static func encode(_ value: URL) -> String {
        MCPToolArgumentEncoder.encode(value)
    }

    public static func encode(_ value: UUID) -> String {
        MCPToolArgumentEncoder.encode(value)
    }

    public static func encode(_ value: Data) -> String {
        MCPToolArgumentEncoder.encode(value)
    }

    public static func encode<T: CaseIterable>(_ value: T) -> String {
        String(describing: value)
    }

    public static func encode(_ values: [Date]) -> [String] {
        MCPToolArgumentEncoder.encode(values)
    }

    public static func encode(_ values: [URL]) -> [String] {
        MCPToolArgumentEncoder.encode(values)
    }

    public static func encode(_ values: [UUID]) -> [String] {
        MCPToolArgumentEncoder.encode(values)
    }

    public static func encode(_ values: [Data]) -> [String] {
        MCPToolArgumentEncoder.encode(values)
    }

    public static func encode<T: CaseIterable>(_ values: [T]) -> [String] {
        values.map { String(describing: $0) }
    }
}
