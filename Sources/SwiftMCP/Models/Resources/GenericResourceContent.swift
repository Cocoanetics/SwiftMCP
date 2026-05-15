import Foundation

/// Generic implementation of MCPResourceContent for simple text resources
public struct GenericResourceContent: MCPResourceContent {
    public let uri: URL
    public let mimeType: String?
    public let text: String?
    public let blob: Data?

    public init(uri: URL, mimeType: String? = nil, text: String? = nil, blob: Data? = nil) {
        self.uri = uri
        self.mimeType = mimeType
        self.text = text
        self.blob = blob
    }

    /// Converts any resource result to an array of MCPResourceContent
    public static func fromResult(_ result: Any, uri: URL, mimeType: String?) -> [MCPResourceContent] {
        if let direct = directResourceContent(from: result) {
            return direct
        }
        if let primitive = primitiveTextContent(from: result, uri: uri, mimeType: mimeType) {
            return primitive
        }
        if let collection = collectionTextContent(from: result, uri: uri, mimeType: mimeType) {
            return collection
        }
        if let encoded = encodableJSONContent(from: result, uri: uri, mimeType: mimeType) {
            return encoded
        }
        // Fallback: use String(describing:)
        let text = String(describing: result)
        return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "text/plain", text: text)]
    }

    /// Returns the result wrapped as-is when it is already a single or array of `MCPResourceContent`,
    /// or an empty array when it is `Void`.
    private static func directResourceContent(from result: Any) -> [MCPResourceContent]? {
        if let resourceContent = result as? MCPResourceContent {
            return [resourceContent]
        }
        if let resourceArray = result as? [MCPResourceContent] {
            return resourceArray
        }
        if type(of: result) == Void.self {
            return []
        }
        return nil
    }

    /// Converts simple scalar results (`String`/`Bool`/`Int`/`Double`) into a single text content.
    private static func primitiveTextContent(
        from result: Any,
        uri: URL,
        mimeType: String?
    ) -> [MCPResourceContent]? {
        let mime = mimeType ?? "text/plain"
        if let str = result as? String {
            return [GenericResourceContent(uri: uri, mimeType: mime, text: str)]
        }
        if let boolVal = result as? Bool {
            return [GenericResourceContent(uri: uri, mimeType: mime, text: String(boolVal))]
        }
        if let intVal = result as? Int {
            return [GenericResourceContent(uri: uri, mimeType: mime, text: String(intVal))]
        }
        if let doubleVal = result as? Double {
            return [GenericResourceContent(uri: uri, mimeType: mime, text: String(doubleVal))]
        }
        return nil
    }

    /// Converts loose collection results (`[Any]` / `[String: Any]`) into a single text content
    /// using `String(describing:)`, matching the historical fallback shape.
    private static func collectionTextContent(
        from result: Any,
        uri: URL,
        mimeType: String?
    ) -> [MCPResourceContent]? {
        let mime = mimeType ?? "text/plain"
        if let arr = result as? [Any] {
            return [GenericResourceContent(uri: uri, mimeType: mime, text: String(describing: arr))]
        }
        if let dict = result as? [String: Any] {
            return [GenericResourceContent(uri: uri, mimeType: mime, text: String(describing: dict))]
        }
        return nil
    }

    /// Serializes any `Encodable` result to pretty-printed JSON, returning `nil` when encoding fails
    /// or `result` is not `Encodable`.
    private static func encodableJSONContent(
        from result: Any,
        uri: URL,
        mimeType: String?
    ) -> [MCPResourceContent]? {
        guard let encodable = result as? Encodable else {
            return nil
        }
        let encoder = MCPJSONCoding.makeWireEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let jsonValue = try? JSONValue(encoding: encodable),
              let data = try? encoder.encode(jsonValue),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "application/json", text: json)]
    }
}
