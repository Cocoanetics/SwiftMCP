import Foundation

/// Helpers for encoding native values into MCP tool argument payloads.
public enum MCPToolArgumentEncoder {
    public static func encode(_ value: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        return formatter.string(from: value)
    }

    public static func encode(_ value: URL) -> String {
        value.absoluteString
    }

    public static func encode(_ value: UUID) -> String {
        value.uuidString
    }

    public static func encode(_ value: Data) -> String {
        value.base64EncodedString()
    }

    public static func encode(_ values: [Date]) -> [String] {
        values.map(encode)
    }

    public static func encode(_ values: [URL]) -> [String] {
        values.map(encode)
    }

    public static func encode(_ values: [UUID]) -> [String] {
        values.map(encode)
    }

    public static func encode(_ values: [Data]) -> [String] {
        values.map(encode)
    }
}
