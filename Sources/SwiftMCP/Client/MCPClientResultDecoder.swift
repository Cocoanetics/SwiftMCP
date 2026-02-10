import Foundation

/// Decodes MCP tool call results into native Swift types.
public enum MCPClientResultDecoder {
    public static func decode(_ type: Void.Type, from text: String) throws -> Void {
        ()
    }

    public static func decode(_ type: MCPText.Type, from text: String) throws -> MCPText {
        let decoder = configuredDecoder()
        if let result = try? decoder.decode(MCPText.self, from: Data(text.utf8)) {
            return result
        }
        if let results = try? decoder.decode([MCPText].self, from: Data(text.utf8)),
           let first = results.first {
            return first
        }
        return MCPText(text)
    }

    public static func decode(_ type: [MCPText].Type, from text: String) throws -> [MCPText] {
        let decoder = configuredDecoder()
        if let results = try? decoder.decode([MCPText].self, from: Data(text.utf8)) {
            return results
        }
        if let result = try? decoder.decode(MCPText.self, from: Data(text.utf8)) {
            return [result]
        }
        return [MCPText(text)]
    }

    public static func decode(_ type: MCPImage.Type, from text: String) throws -> MCPImage {
        let decoder = configuredDecoder()
        if let result = try? decoder.decode(MCPImage.self, from: Data(text.utf8)) {
            return result
        }
        if let results = try? decoder.decode([MCPImage].self, from: Data(text.utf8)),
           let first = results.first {
            return first
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected MCPImage"))
    }

    public static func decode(_ type: [MCPImage].Type, from text: String) throws -> [MCPImage] {
        let decoder = configuredDecoder()
        if let results = try? decoder.decode([MCPImage].self, from: Data(text.utf8)) {
            return results
        }
        if let result = try? decoder.decode(MCPImage.self, from: Data(text.utf8)) {
            return [result]
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected MCPImage array"))
    }

    public static func decode(_ type: MCPAudio.Type, from text: String) throws -> MCPAudio {
        let decoder = configuredDecoder()
        if let result = try? decoder.decode(MCPAudio.self, from: Data(text.utf8)) {
            return result
        }
        if let results = try? decoder.decode([MCPAudio].self, from: Data(text.utf8)),
           let first = results.first {
            return first
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected MCPAudio"))
    }

    public static func decode(_ type: [MCPAudio].Type, from text: String) throws -> [MCPAudio] {
        let decoder = configuredDecoder()
        if let results = try? decoder.decode([MCPAudio].self, from: Data(text.utf8)) {
            return results
        }
        if let result = try? decoder.decode(MCPAudio.self, from: Data(text.utf8)) {
            return [result]
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected MCPAudio array"))
    }

    public static func decode(_ type: MCPResourceLink.Type, from text: String) throws -> MCPResourceLink {
        let decoder = configuredDecoder()
        if let result = try? decoder.decode(MCPResourceLink.self, from: Data(text.utf8)) {
            return result
        }
        if let results = try? decoder.decode([MCPResourceLink].self, from: Data(text.utf8)),
           let first = results.first {
            return first
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected MCPResourceLink"))
    }

    public static func decode(_ type: [MCPResourceLink].Type, from text: String) throws -> [MCPResourceLink] {
        let decoder = configuredDecoder()
        if let results = try? decoder.decode([MCPResourceLink].self, from: Data(text.utf8)) {
            return results
        }
        if let result = try? decoder.decode(MCPResourceLink.self, from: Data(text.utf8)) {
            return [result]
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected MCPResourceLink array"))
    }

    public static func decode(_ type: MCPEmbeddedResource.Type, from text: String) throws -> MCPEmbeddedResource {
        let decoder = configuredDecoder()
        if let result = try? decoder.decode(MCPEmbeddedResource.self, from: Data(text.utf8)) {
            return result
        }
        if let results = try? decoder.decode([MCPEmbeddedResource].self, from: Data(text.utf8)),
           let first = results.first {
            return first
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected MCPEmbeddedResource"))
    }

    public static func decode(_ type: [MCPEmbeddedResource].Type, from text: String) throws -> [MCPEmbeddedResource] {
        let decoder = configuredDecoder()
        if let results = try? decoder.decode([MCPEmbeddedResource].self, from: Data(text.utf8)) {
            return results
        }
        if let result = try? decoder.decode(MCPEmbeddedResource.self, from: Data(text.utf8)) {
            return [result]
        }
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "Expected MCPEmbeddedResource array"))
    }

    public static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        let decoder = configuredDecoder()

        let data = Data(text.utf8)
        do {
            return try decoder.decode(T.self, from: data)
        } catch let firstError {
            // The server wraps arrays of objects in {"items":[...]} via MCPArrayOutputWrapper.
            // Transparently unwrap the "items" key so callers can decode [Element] directly.
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let items = object["items"] {
                let itemsData = try JSONSerialization.data(withJSONObject: items, options: [.sortedKeys])
                if let result = try? decoder.decode(T.self, from: itemsData) {
                    return result
                }
            }

            // Fallback: try wrapping the text in quotes (for plain string values)
            let quoted = "\"\(text)\""
            let quotedData = Data(quoted.utf8)
            do {
                return try decoder.decode(T.self, from: quotedData)
            } catch {
                throw firstError
            }
        }
    }

    private static func configuredDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithTimeZone
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        return decoder
    }
}
