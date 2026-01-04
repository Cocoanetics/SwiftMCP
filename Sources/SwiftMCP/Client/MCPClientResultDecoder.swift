import Foundation

/// Decodes MCP tool call results into native Swift types.
public enum MCPClientResultDecoder {
    public static func decode(_ type: Void.Type, from text: String) throws -> Void {
        ()
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithTimeZone
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )

        let data = Data(text.utf8)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let quoted = "\"\(text)\""
            let quotedData = Data(quoted.utf8)
            return try decoder.decode(T.self, from: quotedData)
        }
    }
}
