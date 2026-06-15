import Foundation
import SwiftMCP

extension ProxyGenerator {
    // swiftlint:disable:next function_parameter_count
    static func makeActorSource(
        typeName: String,
        tools: [MCPTool],
        resources: [SimpleResource],
        resourceTemplates: [SimpleResourceTemplate],
        prompts: [Prompt],
        supportsResources: Bool,
        supportsPrompts: Bool,
        returnTypes: [String: OpenAPIReturnInfo],
        typeDefinitions: [String],
        typeDocComment: [String],
        metadata: HeaderMetadata,
        functionNaming: FunctionNaming = .lowerCamelCase
    ) -> String {
        var lines: [String] = []
        if !typeDocComment.isEmpty {
            lines.append(contentsOf: typeDocComment)
        }
        lines.append("public enum \(typeName) {")
        appendTypeDefinitions(typeDefinitions, into: &lines)
        appendMetadataSection(metadata: metadata, into: &lines)
        appendClientHeader(typeName: typeName, metadata: metadata, into: &lines)

        let clientBody = makeClientBody(
            tools: tools,
            resources: resources,
            resourceTemplates: resourceTemplates,
            prompts: prompts,
            supportsResources: supportsResources,
            supportsPrompts: supportsPrompts,
            returnTypes: returnTypes,
            functionNaming: functionNaming
        )

        // Indent client body one extra level into the enum namespace
        for line in clientBody {
            lines.append(line.isEmpty ? "" : "    \(line)")
        }

        lines.append("    }")  // close Client actor
        lines.append("}")  // close namespace enum
        return lines.joined(separator: "\n")
    }

    private static func appendTypeDefinitions(_ typeDefinitions: [String], into lines: inout [String]) {
        if !typeDefinitions.isEmpty {
            lines.append("    // MARK: - Declarations")
            lines.append(contentsOf: indentDefinitions(typeDefinitions, indent: "    "))
            lines.append("")
        }
    }

    private static func appendMetadataSection(metadata: HeaderMetadata, into lines: inout [String]) {
        let name = swiftOptionalStringLiteral(metadata.serverName)
        let title = swiftOptionalStringLiteral(metadata.serverTitle)
        let website = swiftOptionalStringLiteral(metadata.serverWebsiteUrl)
        let icons = metadata.serverIconURLs.map { swiftOptionalStringLiteral($0) }.joined(separator: ", ")
        lines.append("    // MARK: - Metadata")
        lines.append("    public static let serverName: String? = \(name)")
        lines.append("    public static let serverTitle: String? = \(title)")
        lines.append("    public static let serverWebsiteUrl: String? = \(website)")
        lines.append("    public static let serverIconURLs: [String] = [\(icons)]")
        lines.append("")
    }

    private static func appendClientHeader(
        typeName: String,
        metadata: HeaderMetadata,
        into lines: inout [String]
    ) {
        // Derive client name from server name (PascalCased)
        // e.g., server "xcode-tools" → "XcodeTools Client"
        let clientBaseName = metadata.serverName.map { pascalCase($0) } ?? typeName
        let defaultClientName = "\(clientBaseName) Client"
        lines.append("    // MARK: - Client")
        lines.append("    public actor Client {")
        lines.append("        public let proxy: MCPServerProxy")
        lines.append("        public let clientName: String")
        lines.append("        public let clientVersion: String")
        lines.append("")
        let initSignature = "proxy: MCPServerProxy, " +
            "clientName: String = \"\(defaultClientName)\", " +
            "clientVersion: String = \"1.0.0\""
        lines.append("        public init(\(initSignature)) {")
        lines.append("            self.proxy = proxy")
        lines.append("            self.clientName = clientName")
        lines.append("            self.clientVersion = clientVersion")
        lines.append("        }")
        lines.append("")
        lines.append("        /// Connects to the MCP server, identifying as this client.")
        lines.append("        public func connect() async throws {")
        lines.append("            try await proxy.connect(clientName: clientName, clientVersion: clientVersion)")
        lines.append("        }")
    }

    // swiftlint:disable:next function_parameter_count
    private static func makeClientBody(
        tools: [MCPTool],
        resources: [SimpleResource],
        resourceTemplates: [SimpleResourceTemplate],
        prompts: [Prompt],
        supportsResources: Bool,
        supportsPrompts: Bool,
        returnTypes: [String: OpenAPIReturnInfo],
        functionNaming: FunctionNaming
    ) -> [String] {
        var clientBody: [String] = []

        let sortedTools = tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        let includesResources = supportsResources || !resources.isEmpty || !resourceTemplates.isEmpty
        let includesPrompts = supportsPrompts || !prompts.isEmpty

        var usedMethodNames = Set(sortedTools.map { swiftIdentifier(from: $0.name, lowerCamel: true) })
        if includesResources {
            usedMethodNames.formUnion(["listResources", "listResourceTemplates", "readResource"])
        }
        if includesPrompts {
            usedMethodNames.formUnion(["listPrompts", "getPrompt"])
        }

        appendToolMethods(
            sortedTools: sortedTools,
            returnTypes: returnTypes,
            functionNaming: functionNaming,
            into: &clientBody
        )

        if includesResources {
            clientBody.append("")
            clientBody.append("    // MARK: - Resources")
            clientBody.append("")
            clientBody.append(contentsOf: makeResourceMethodLines(
                resources: resources,
                resourceTemplates: resourceTemplates,
                usedMethodNames: &usedMethodNames
            ))
        }

        if includesPrompts {
            clientBody.append("")
            clientBody.append("    // MARK: - Prompts")
            clientBody.append("")
            clientBody.append(contentsOf: makePromptMethodLines(
                prompts: prompts,
                usedMethodNames: &usedMethodNames
            ))
        }

        return clientBody
    }

    private static func appendToolMethods(
        sortedTools: [MCPTool],
        returnTypes: [String: OpenAPIReturnInfo],
        functionNaming: FunctionNaming,
        into clientBody: inout [String]
    ) {
        if !sortedTools.isEmpty {
            clientBody.append("")
            clientBody.append("    // MARK: - Functions")
        }
        for tool in sortedTools {
            clientBody.append("")
            let returnInfo = returnTypes[tool.name]
            clientBody.append(contentsOf: makeMethodLines(
                tool: tool,
                returnInfo: returnInfo,
                functionNaming: functionNaming
            ))
        }
    }

    static func swiftOptionalStringLiteral(_ value: String?) -> String {
        guard let value else { return "nil" }
        // Escape for embedding as a Swift double-quoted string literal. Server
        // metadata (e.g. a free-form title) is untrusted display text, so it may
        // contain backslashes, quotes or newlines. Backslash MUST be escaped
        // first so the backslashes introduced below are not double-escaped.
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
        return "\"\(escaped)\""
    }

    static func indentDefinitions(_ definitions: [String], indent: String) -> [String] {
        var lines: [String] = []
        for (index, definition) in definitions.enumerated() {
            let indented = definition
                .split(separator: "\n", omittingEmptySubsequences: false)
                .map { line -> String in
                    if line.isEmpty {
                        return ""
                    }
                    return indent + line
                }
            lines.append(contentsOf: indented)
            if index < definitions.count - 1 {
                lines.append("")
            }
        }
        return lines
    }
}
