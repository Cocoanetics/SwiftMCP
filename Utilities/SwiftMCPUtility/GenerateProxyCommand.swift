import Foundation
import ArgumentParser
import SwiftMCP
import SwiftSyntax
import SwiftSyntaxBuilder

struct GenerateProxyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate-proxy",
        abstract: "Generate a Swift proxy from MCP tools",
        discussion: """
  Connect to an MCP server, read the tools list, and generate a Swift proxy.

  Examples:
    SwiftMCPUtility generate-proxy --sse http://localhost:8080/sse -o ToolsProxy.swift
    SwiftMCPUtility generate-proxy --command "npx -y @modelcontextprotocol/server-filesystem"
    SwiftMCPUtility generate-proxy --config mcp.json --name FileToolsProxy
"""
    )

    @OptionGroup
    var connection: ConnectionOptions

    @Option(name: .long, help: "Name of the generated proxy type")
    var name: String?

    @Option(name: [.customShort("o"), .long], help: "Write the generated Swift file to this path")
    var output: String?

    func run() async throws {
        let config = try UtilitySupport.makeConfig(from: connection)
        let proxy = MCPServerProxy(config: config)

        defer {
            Task {
                await proxy.disconnect()
            }
        }

        try await proxy.connect()
        let tools = try await proxy.listTools()
        let serverName = await proxy.serverName
        let typeName = name ?? ProxyGenerator.defaultTypeName(serverName: serverName)
        let source = ProxyGenerator.generate(typeName: typeName, tools: tools)
        let outputText = source.description
        try UtilitySupport.writeOutput(outputText, to: output)
    }
}

private enum ProxyGenerator {
    static func generate(typeName: String, tools: [MCPTool]) -> SourceFileSyntax {
        let actorSource = makeActorSource(typeName: typeName, tools: tools)
        return SourceFileSyntax {
            DeclSyntax("import Foundation")
            DeclSyntax("import SwiftMCP")
            DeclSyntax(stringLiteral: actorSource)
        }
    }

    static func defaultTypeName(serverName: String?) -> String {
        let base = serverName.flatMap { pascalCase($0) } ?? "MCPServer"
        return "\(base)Proxy"
    }

    private static func makeActorSource(typeName: String, tools: [MCPTool]) -> String {
        var lines: [String] = []
        lines.append("public actor \(typeName) {")
        lines.append("    public let proxy: MCPServerProxy")
        lines.append("")
        lines.append("    public init(proxy: MCPServerProxy) {")
        lines.append("        self.proxy = proxy")
        lines.append("    }")

        let sortedTools = tools.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for tool in sortedTools {
            lines.append("")
            lines.append(contentsOf: makeMethodLines(tool: tool))
        }

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    private static func makeMethodLines(tool: MCPTool) -> [String] {
        var lines: [String] = []
        let methodName = swiftIdentifier(from: tool.name, lowerCamel: true)

        let parameters = methodParameters(for: tool)
        lines.append(contentsOf: docCommentLines(tool: tool, parameters: parameters))

        let signature = parameters.map { $0.signature }.joined(separator: ", ")
        lines.append("    public func \(methodName)(\(signature)) async throws -> String {")

        if parameters.isEmpty {
            lines.append("        return try await proxy.callTool(\"\(tool.name)\")")
            lines.append("    }")
            return lines
        }

        lines.append("        var arguments: [String: any Sendable] = [:]")
        for param in parameters {
            let key = param.originalName
            if param.isOptional {
                if param.needsEncoding {
                    lines.append("        if let \(param.swiftName) { arguments[\"\(key)\"] = MCPToolArgumentEncoder.encode(\(param.swiftName)) }")
                } else {
                    lines.append("        if let \(param.swiftName) { arguments[\"\(key)\"] = \(param.swiftName) }")
                }
            } else {
                if param.needsEncoding {
                    lines.append("        arguments[\"\(key)\"] = MCPToolArgumentEncoder.encode(\(param.swiftName))")
                } else {
                    lines.append("        arguments[\"\(key)\"] = \(param.swiftName)")
                }
            }
        }
        lines.append("        return try await proxy.callTool(\"\(tool.name)\", arguments: arguments)")
        lines.append("    }")
        return lines
    }

    private static func docCommentLines(tool: MCPTool, parameters: [MethodParameter]) -> [String] {
        var lines: [String] = []
        var bodyLines: [String] = []

        if let description = tool.description, !description.isEmpty {
            for line in description.split(separator: "\n") {
                bodyLines.append(String(line))
            }
        }

        for param in parameters {
            if let docLine = param.docLine, !docLine.isEmpty {
                bodyLines.append("- Parameter \(param.swiftName): \(docLine)")
            }
        }

        if bodyLines.isEmpty {
            return lines
        }

        lines.append("    /**")
        for bodyLine in bodyLines {
            lines.append("     \(bodyLine)")
        }
        lines.append("     */")
        return lines
    }

    private struct MethodParameter {
        let originalName: String
        let swiftName: String
        let signature: String
        let isOptional: Bool
        let needsEncoding: Bool
        let docLine: String?
    }

    private static func methodParameters(for tool: MCPTool) -> [MethodParameter] {
        guard case .object(let object) = tool.inputSchema else {
            return []
        }

        let required = Set(object.required)
        let sortedKeys = object.properties.keys.sorted()
        return sortedKeys.compactMap { key in
            guard let schema = object.properties[key] else {
                return nil
            }
            let swiftName = swiftIdentifier(from: key, lowerCamel: true)
            let typeInfo = swiftTypeInfo(for: schema)
            let isOptional = !required.contains(key)
            let typeName = isOptional ? "\(typeInfo.typeName)?" : typeInfo.typeName
            let defaultValue = isOptional ? " = nil" : ""
            let signature = "\(swiftName): \(typeName)\(defaultValue)"
            let docLine = parameterDocLine(schema: schema)
            return MethodParameter(
                originalName: key,
                swiftName: swiftName,
                signature: signature,
                isOptional: isOptional,
                needsEncoding: typeInfo.needsEncoding,
                docLine: docLine
            )
        }
    }

    private struct SwiftTypeInfo {
        let typeName: String
        let needsEncoding: Bool
    }

    private static func swiftTypeInfo(for schema: JSONSchema) -> SwiftTypeInfo {
        switch schema {
            case .string(_, _, let format, _, _):
                switch format ?? "" {
                    case "date-time":
                        return SwiftTypeInfo(typeName: "Date", needsEncoding: true)
                    case "uri":
                        return SwiftTypeInfo(typeName: "URL", needsEncoding: true)
                    case "uuid":
                        return SwiftTypeInfo(typeName: "UUID", needsEncoding: true)
                    case "byte":
                        return SwiftTypeInfo(typeName: "Data", needsEncoding: true)
                    default:
                        return SwiftTypeInfo(typeName: "String", needsEncoding: false)
                }
            case .number:
                return SwiftTypeInfo(typeName: "Double", needsEncoding: false)
            case .boolean:
                return SwiftTypeInfo(typeName: "Bool", needsEncoding: false)
            case .array(let items, _, _):
                let elementInfo = swiftTypeInfo(for: items)
                return SwiftTypeInfo(typeName: "[\(elementInfo.typeName)]", needsEncoding: elementInfo.needsEncoding)
            case .object:
                return SwiftTypeInfo(typeName: "[String: any Sendable]", needsEncoding: false)
            case .enum:
                return SwiftTypeInfo(typeName: "String", needsEncoding: false)
        }
    }

    private static func parameterDocLine(schema: JSONSchema) -> String? {
        var parts: [String] = []
        if let description = schemaDescription(schema), !description.isEmpty {
            parts.append(description)
        }

        if case .enum(let values, _, _, _) = schema, !values.isEmpty {
            parts.append("Values: \(values.joined(separator: ", "))")
        }

        if parts.isEmpty {
            return nil
        }
        return parts.joined(separator: " ")
    }

    private static func schemaDescription(_ schema: JSONSchema) -> String? {
        switch schema {
            case .string(_, let description, _, _, _):
                return description
            case .number(_, let description, _, _):
                return description
            case .boolean(_, let description, _):
                return description
            case .array(_, _, let description):
                return description
            case .object(let object):
                return object.description
            case .enum(_, _, let description, _):
                return description
        }
    }

    private static func pascalCase(_ string: String) -> String {
        let parts = string
            .split { !$0.isLetter && !$0.isNumber }
            .map { $0.lowercased() }
        let joined = parts.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        return joined.isEmpty ? "MCPServer" : joined
    }

    private static func swiftIdentifier(from raw: String, lowerCamel: Bool) -> String {
        let parts = raw.split { !$0.isLetter && !$0.isNumber }
        if parts.isEmpty {
            return "value"
        }

        let first = parts.first!.lowercased()
        let rest = parts.dropFirst().map { $0.lowercased().capitalized }
        var combined = lowerCamel ? ([first] + rest).joined() : ([first.capitalized] + rest).joined()

        if let firstChar = combined.first, firstChar.isNumber {
            combined = "_" + combined
        }

        if reservedKeywords.contains(combined) {
            combined += "_"
        }

        return combined
    }

    private static let reservedKeywords: Set<String> = [
        "associatedtype", "class", "deinit", "enum", "extension", "fileprivate",
        "func", "import", "init", "inout", "internal", "let", "open", "operator",
        "private", "protocol", "public", "static", "struct", "subscript", "typealias",
        "var", "break", "case", "continue", "default", "defer", "do", "else", "fallthrough",
        "for", "guard", "if", "in", "repeat", "return", "switch", "where", "while",
        "as", "catch", "false", "is", "nil", "rethrows", "super", "self", "Self",
        "throw", "throws", "true", "try", "Any"
    ]
}
