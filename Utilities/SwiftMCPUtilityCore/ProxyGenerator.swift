import Foundation
#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif
import SwiftMCP
import SwiftSyntax
import SwiftSyntaxBuilder

public enum ProxyGenerator {
    public struct HeaderMetadata: Sendable {
        public let fileName: String
        public let serverName: String?
        public let serverVersion: String?
        public let serverDescription: String?
        public let source: String?
        public let openAPI: String?
        public let serverTitle: String?
        public let serverWebsiteUrl: String?
        public let serverIconURLs: [String]

        public init(
            fileName: String,
            serverName: String?,
            serverVersion: String?,
            serverDescription: String?,
            source: String?,
            openAPI: String?,
            serverTitle: String? = nil,
            serverWebsiteUrl: String? = nil,
            serverIconURLs: [String] = []
        ) {
            self.fileName = fileName
            self.serverName = serverName
            self.serverVersion = serverVersion
            self.serverDescription = serverDescription
            self.source = source
            self.openAPI = openAPI
            self.serverTitle = serverTitle
            self.serverWebsiteUrl = serverWebsiteUrl
            self.serverIconURLs = serverIconURLs
        }
    }

    /// Naming convention for generated Swift function names.
    public enum FunctionNaming {
        /// Use the tool name as-is (no conversion).
        case verbatim
        /// Convert to lowerCamelCase (default — idiomatic Swift).
        case lowerCamelCase
        /// Convert to snake_case.
        case snakeCase
    }

    struct MethodParameter {
        let originalName: String
        let swiftName: String
        let signature: String
        let isOptional: Bool
        let needsEncoding: Bool
        let docLine: String?
    }

    struct TemplateVariable {
        let name: String
        let isOptional: Bool
    }

    public static func generate(
        typeName: String,
        tools: [MCPTool],
        resources: [SimpleResource] = [],
        resourceTemplates: [SimpleResourceTemplate] = [],
        prompts: [Prompt] = [],
        supportsResources: Bool = false,
        supportsPrompts: Bool = false,
        openapiReturnSchemas: [String: OpenAPIReturnInfo] = [:],
        functionNaming: FunctionNaming = .lowerCamelCase,
        fileName: String? = nil,
        headerMetadata: HeaderMetadata? = nil
    ) -> SourceFileSyntax {
        let registry = OpenAPITypeRegistry()
        let returnTypes = buildReturnTypes(
            tools: tools,
            openapiReturnSchemas: openapiReturnSchemas,
            registry: registry
        )
        let typeDefinitions = registry.renderDefinitions()
        let resolvedFileName = fileName ?? "\(typeName).swift"
        let metadata = headerMetadata ?? HeaderMetadata(
            fileName: resolvedFileName,
            serverName: nil,
            serverVersion: nil,
            serverDescription: nil,
            source: nil,
            openAPI: nil
        )
        let headerComment = makeHeaderComment(metadata: metadata)
        let typeDocComment = makeTypeDocCommentLines(metadata: metadata)
        let actorSource = makeActorSource(
            typeName: typeName,
            tools: tools,
            resources: resources,
            resourceTemplates: resourceTemplates,
            prompts: prompts,
            supportsResources: supportsResources,
            supportsPrompts: supportsPrompts,
            returnTypes: returnTypes,
            typeDefinitions: typeDefinitions,
            typeDocComment: typeDocComment,
            metadata: metadata,
            functionNaming: functionNaming
        )

        let headerAndImports = "\(headerComment)\n\nimport Foundation\nimport SwiftMCP\n"

        return SourceFileSyntax {
            DeclSyntax(stringLiteral: headerAndImports)
            DeclSyntax(stringLiteral: "\n\(actorSource)")
        }
    }

    public static func defaultTypeName(serverName: String?) -> String {
        serverName.flatMap { pascalCase($0) } ?? "MCPServer"
    }

    static func wrapperDocCommentLines(
        description: String?,
        parameters: [MethodParameter]
    ) -> [String] {
        var bodyLines: [String] = []

        if let description, !description.isEmpty {
            for line in description.split(separator: "\n", omittingEmptySubsequences: false) {
                bodyLines.append(String(line))
            }
        }

        for parameter in parameters {
            if let docLine = parameter.docLine, !docLine.isEmpty {
                bodyLines.append("- Parameter \(parameter.swiftName): \(docLine)")
            }
        }

        guard !bodyLines.isEmpty else {
            return []
        }

        var lines: [String] = []
        for bodyLine in bodyLines {
            lines.append("    /// \(bodyLine)")
        }
        return lines
    }

    static func uniqueMethodName(
        candidate: String,
        suffix: String,
        usedMethodNames: inout Set<String>
    ) -> String {
        if usedMethodNames.insert(candidate).inserted {
            return candidate
        }

        let suffixedCandidate = candidate + suffix
        if usedMethodNames.insert(suffixedCandidate).inserted {
            return suffixedCandidate
        }

        var index = 2
        while true {
            let indexedCandidate = "\(suffixedCandidate)\(index)"
            if usedMethodNames.insert(indexedCandidate).inserted {
                return indexedCandidate
            }
            index += 1
        }
    }
}
