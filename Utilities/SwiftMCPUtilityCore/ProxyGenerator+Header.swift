import Foundation
import SwiftMCP

extension ProxyGenerator {
    static func makeHeaderComment(metadata: HeaderMetadata) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone.current
        formatter.formatOptions = [.withInternetDateTime, .withTimeZone]
        let timestamp = formatter.string(from: Date())

        var lines: [String] = [
            "//",
            "//  \(metadata.fileName)",
            "//  Generated: \(timestamp)",
            "//  Server: \(serverDisplayName(from: metadata))"
        ]

        if let source = metadata.source, !source.isEmpty {
            lines.append("//  Source: \(source)")
        }
        if let openAPI = metadata.openAPI, !openAPI.isEmpty {
            lines.append("//  OpenAPI: \(openAPI)")
        }

        lines.append("//")
        return lines.joined(separator: "\n")
    }

    static func makeTypeDocCommentLines(metadata: HeaderMetadata) -> [String] {
        let summary = typeDocSummary(metadata: metadata)
        var commentBody = summary
        if let description = metadata.serverDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            commentBody = description
        }
        if let openAPI = metadata.openAPI, !openAPI.isEmpty {
            commentBody += "\n\nReturn types are enhanced using OpenAPI metadata."
        }

        return docBlockLines(commentBody)
    }

    private static func typeDocSummary(metadata: HeaderMetadata) -> String {
        let name = metadata.serverName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let version = metadata.serverVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !name.isEmpty {
            if !version.isEmpty {
                return "A generated proxy for the \(name) MCP server (\(version))."
            }
            return "A generated proxy for the \(name) MCP server."
        }
        return "A generated MCP server proxy."
    }

    private static func docBlockLines(_ text: String) -> [String] {
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { "/// \($0)" }
    }

    private static func serverDisplayName(from metadata: HeaderMetadata) -> String {
        let name = metadata.serverName ?? "unknown"
        let version = metadata.serverVersion ?? "unknown"
        return "\(name) (\(version))"
    }

    static func buildReturnTypes(
        tools: [MCPTool],
        openapiReturnSchemas: [String: OpenAPIReturnInfo],
        registry: OpenAPITypeRegistry
    ) -> [String: OpenAPIReturnInfo] {
        var results: [String: OpenAPIReturnInfo] = [:]
        for tool in tools {
            guard let entry = returnInfoEntry(
                for: tool,
                openapiReturnSchemas: openapiReturnSchemas,
                registry: registry
            ) else {
                continue
            }
            results[tool.name] = entry
        }
        return results
    }

    private static func returnInfoEntry(
        for tool: MCPTool,
        openapiReturnSchemas: [String: OpenAPIReturnInfo],
        registry: OpenAPITypeRegistry
    ) -> OpenAPIReturnInfo? {
        let schema: JSONSchema
        let description: String?
        if let outputSchema = tool.outputSchema {
            schema = outputSchema
            description = openapiReturnSchemas[tool.name]?.description ?? schemaDescription(outputSchema)
        } else if let openapiInfo = openapiReturnSchemas[tool.name] {
            schema = openapiInfo.schema
            description = openapiInfo.description
        } else {
            return nil
        }

        let baseName = "\(pascalCase(tool.name))Response"
        let typeName = registry.swiftType(for: schema, suggestedName: baseName)
        return OpenAPIReturnInfo(
            typeName: typeName,
            schema: schema,
            description: description
        )
    }
}
