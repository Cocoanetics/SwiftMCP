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
        // If already MCPResourceContent
        if let resourceContent = result as? MCPResourceContent {
            return [resourceContent]
        } else if let resourceArray = result as? [MCPResourceContent] {
            return resourceArray
        } else if type(of: result) == Void.self {
            return []
        } else if let str = result as? String {
            return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "text/plain", text: str)]
        } else if let boolVal = result as? Bool {
            return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "text/plain", text: String(boolVal))]
        } else if let intVal = result as? Int {
            return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "text/plain", text: String(intVal))]
        } else if let doubleVal = result as? Double {
            return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "text/plain", text: String(doubleVal))]
        } else if let arr = result as? [Any] {
            let text = String(describing: arr)
            return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "text/plain", text: text)]
        } else if let dict = result as? [String: Any] {
            let text = String(describing: dict)
            return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "text/plain", text: text)]
        } else if let encodable = result as? Encodable {
            // Try to encode to JSON string
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(AnyEncodable(encodable)),
			   let json = String(data: data, encoding: .utf8) {
                return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "application/json", text: json)]
            }
        }
        // Fallback: use String(describing:)
        let text = String(describing: result)
        return [GenericResourceContent(uri: uri, mimeType: mimeType ?? "text/plain", text: text)]
    }
}



/// Helper to encode any Encodable type
private struct AnyEncodable: Encodable {
    let value: Encodable
    init(_ value: Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
} 
