import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import SwiftMCP

public struct OpenAPIReturnInfo: Sendable {
    public let typeName: String
    public let schema: JSONSchema
    public let description: String?

    public init(typeName: String, schema: JSONSchema, description: String?) {
        self.typeName = typeName
        self.schema = schema
        self.description = description
    }
}

public enum OpenAPIProxyLoader {
    public static func loadReturnSchemas(from value: String?) async throws -> [String: OpenAPIReturnInfo] {
        guard let value, !value.isEmpty else { return [:] }
        let url = openAPIURL(from: value)
        let data: Data
        if url.isFileURL {
            data = try Data(contentsOf: url)
        } else {
            let (remoteData, _) = try await URLSession.shared.data(from: url)
            data = remoteData
        }

        let spec = try JSONDecoder().decode(OpenAPIProxySpec.self, from: data)
        return spec.returnSchemasByOperationId()
    }

    private static func openAPIURL(from value: String) -> URL {
        if let url = URL(string: value), url.scheme != nil {
            return url
        }
        return URL(fileURLWithPath: value)
    }
}

struct OpenAPIProxySpec: Decodable {
    struct PathItem: Decodable {
        let post: Operation?
    }

    struct Operation: Decodable {
        let operationId: String?
        let description: String?
        let requestBody: RequestBody?
        let responses: [String: Response]
    }

    struct RequestBody: Decodable {
        let content: [String: MediaType]?
    }

    struct Response: Decodable {
        let description: String?
        let content: [String: MediaType]?
    }

    struct MediaType: Decodable {
        let schema: JSONSchema?
    }

    let paths: [String: PathItem]

    func returnSchemasByOperationId() -> [String: OpenAPIReturnInfo] {
        var results: [String: OpenAPIReturnInfo] = [:]
        for item in paths.values {
            guard let operation = item.post,
                  let operationId = operation.operationId else { continue }
            guard let response = pickResponse(operation.responses),
                  let schema = pickSchema(response.content) else { continue }
            results[operationId] = OpenAPIReturnInfo(
                typeName: "String",
                schema: schema,
                description: response.description
            )
        }
        return results
    }

    private func pickResponse(_ responses: [String: Response]) -> Response? {
        if let response = responses["200"] {
            return response
        }
        let twoHundreds = responses.keys.filter { $0.hasPrefix("2") }.sorted()
        if let key = twoHundreds.first {
            return responses[key]
        }
        return nil
    }

    private func pickSchema(_ content: [String: MediaType]?) -> JSONSchema? {
        guard let content else { return nil }
        if let schema = content["application/json"]?.schema {
            return schema
        }
        return content.values.first?.schema
    }
}
