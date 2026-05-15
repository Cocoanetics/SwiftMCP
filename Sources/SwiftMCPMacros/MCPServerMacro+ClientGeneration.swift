//
//  MCPServerMacro+ClientGeneration.swift
//  SwiftMCPMacros
//
//  Code generation for the nested `Client` type emitted by `@MCPServer`.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

extension MCPServerMacro {
    struct ClientParameter {
        let name: String
        let label: String
        let typeString: String
        let defaultValue: String?
        let isOptional: Bool
    }

    struct ClientFunctionMetadata {
        let kind: ClientFunctionKind
        let name: String
        let documentation: Documentation
        let parameters: [ClientParameter]
        let returnTypeString: String
        let hasReturnClause: Bool
        let isAsync: Bool
        let isThrowing: Bool
        let throwsKeyword: String?
        let propagatedAttributes: [String]
    }

    enum ClientFunctionKind {
        case tool
        case resource(templates: [String])
        case prompt
    }

    static func makeClientType(
        toolFunctions: [FunctionDeclSyntax],
        mcpTools: [(functionName: String, toolName: String)] = [],
        resourceFunctions: [FunctionDeclSyntax],
        promptFunctions: [FunctionDeclSyntax],
        serverDescription: String?
    ) -> String {
        // Build a lookup from function name → wire tool name
        let toolNameMap = Dictionary(mcpTools.map { ($0.functionName, $0.toolName) }, uniquingKeysWith: { _, last in last })
        var lines: [String] = []
        lines.append(contentsOf: clientTypeDocCommentLines(description: serverDescription))
        lines.append("public struct Client: Sendable {")
        lines.append("    public let proxy: MCPServerProxy")
        lines.append("")
        lines.append(contentsOf: initDocCommentLines())
        lines.append("    public init(proxy: MCPServerProxy) {")
        lines.append("        self.proxy = proxy")
        lines.append("    }")

        lines.append(contentsOf: clientToolMethodLines(toolFunctions: toolFunctions, toolNameMap: toolNameMap))
        lines.append(contentsOf: clientResourceSectionLines(resourceFunctions: resourceFunctions))
        lines.append(contentsOf: clientPromptSectionLines(promptFunctions: promptFunctions))

        lines.append("}")
        return lines.joined(separator: "\n")
    }

    static func clientToolMethodLines(
        toolFunctions: [FunctionDeclSyntax],
        toolNameMap: [String: String]
    ) -> [String] {
        var lines: [String] = []
        if !toolFunctions.isEmpty {
            lines.append("")
            lines.append("    // MARK: - Tools")
        }
        for funcDecl in toolFunctions {
            let funcName = funcDecl.name.text
            let wireToolName = toolNameMap[funcName]
            let metadata = clientFunctionMetadata(from: funcDecl, kind: .tool)
            lines.append("")
            lines.append(contentsOf: makeClientMethodLines(metadata: metadata, wireToolName: wireToolName))
        }
        return lines
    }

    static func clientResourceSectionLines(resourceFunctions: [FunctionDeclSyntax]) -> [String] {
        guard !resourceFunctions.isEmpty else { return [] }
        return [
            "",
            "    // MARK: - Resources",
            "",
            "    public func listResources() async throws -> [SimpleResource] {",
            "        try await proxy.listResources()",
            "    }",
            "",
            "    public func listResourceTemplates() async throws -> [SimpleResourceTemplate] {",
            "        try await proxy.listResourceTemplates()",
            "    }",
            "",
            "    public func readResource(uri: URL) async throws -> [GenericResourceContent] {",
            "        try await proxy.readResource(uri: uri)",
            "    }"
        ]
    }

    static func clientPromptSectionLines(promptFunctions: [FunctionDeclSyntax]) -> [String] {
        guard !promptFunctions.isEmpty else { return [] }
        return [
            "",
            "    // MARK: - Prompts",
            "",
            "    public func listPrompts() async throws -> [Prompt] {",
            "        try await proxy.listPrompts()",
            "    }",
            "",
            "    public func getPrompt(name: String, arguments: JSONDictionary = [:]) async throws -> PromptResult {",
            "        try await proxy.getPrompt(name: name, arguments: arguments)",
            "    }"
        ]
    }

    static func clientFunctionMetadata(
        from funcDecl: FunctionDeclSyntax,
        kind: ClientFunctionKind,
        generatedName: String? = nil
    ) -> ClientFunctionMetadata {
        let documentation = Documentation(from: funcDecl.leadingTrivia.description)
        let parameters = funcDecl.signature.parameterClause.parameters.map { param -> ClientParameter in
            let name = param.secondName?.text ?? param.firstName.text
            let label = param.firstName.text
            let typeString = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let defaultValue = param.defaultValue?.value.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let isOptional = param.type.is(OptionalTypeSyntax.self)
                || param.type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
                || typeString.hasSuffix("?")
                || typeString.hasSuffix("!")
            return ClientParameter(
                name: name,
                label: label,
                typeString: typeString,
                defaultValue: defaultValue,
                isOptional: isOptional
            )
        }

        let returnClause = funcDecl.signature.returnClause
        let returnTypeString = returnClause?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Void"
        let effectSpecifiers = funcDecl.signature.effectSpecifiers
        let isAsync = effectSpecifiers?.asyncSpecifier != nil
        let throwsClause = effectSpecifiers?.throwsClause
        let throwsKeyword = throwsClause?.description.trimmingCharacters(in: .whitespacesAndNewlines)
        let isThrowing = true

        return ClientFunctionMetadata(
            kind: kind,
            name: generatedName ?? funcDecl.name.text,
            documentation: documentation,
            parameters: parameters,
            returnTypeString: returnTypeString,
            hasReturnClause: returnClause != nil,
            isAsync: isAsync,
            isThrowing: isThrowing,
            throwsKeyword: throwsKeyword ?? "throws",
            propagatedAttributes: propagatedAttributes(for: funcDecl)
        )
    }

    static func propagatedAttributes(for funcDecl: FunctionDeclSyntax) -> [String] {
        var attributes: [String] = []
        for attr in funcDecl.attributes {
            guard let attribute = attr.as(AttributeSyntax.self) else { continue }
            let attributeName = attribute.attributeName.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if attributeName.isEmpty { continue }
            if ["MCPTool", "MCPResource", "MCPPrompt", "MCPServer", "MCPToolProvider", "Schema", "MCPExtension"].contains(attributeName) {
                continue
            }
            let trimmed = attribute.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                attributes.append(trimmed)
            }
        }
        return attributes
    }

    static func docCommentLines(for metadata: ClientFunctionMetadata) -> [String] {
        var bodyLines: [String] = []
        if !metadata.documentation.description.isEmpty {
            for line in metadata.documentation.description.split(separator: "\n") {
                bodyLines.append(String(line))
            }
        }

        for parameter in metadata.parameters {
            if let description = metadata.documentation.parameters[parameter.name], !description.isEmpty {
                bodyLines.append("- Parameter \(parameter.name): \(description)")
            }
        }

        if let returns = metadata.documentation.returns, !returns.isEmpty {
            bodyLines.append("- Returns: \(returns)")
        }

        guard !bodyLines.isEmpty else { return [] }

        var lines: [String] = []
        lines.append("    /**")
        for bodyLine in bodyLines {
            lines.append("     \(bodyLine)")
        }
        lines.append("     */")
        return lines
    }

    static func clientTypeDocCommentLines(description: String?) -> [String] {
        guard let description, !description.isEmpty else { return [] }
        let bodyLines = description.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        return blockDocCommentLines(bodyLines, indent: "")
    }

    static func initDocCommentLines() -> [String] {
        let bodyLines = [
            "Creates a client using the provided proxy.",
            "- Parameter proxy: The proxy used to call server tools, resources, and prompts."
        ]
        return blockDocCommentLines(bodyLines, indent: "    ")
    }

    static func encodedArgumentLines(
        for parameters: [ClientParameter],
        variableName: String,
        indent: String
    ) -> [String] {
        guard !parameters.isEmpty else { return [] }
        var lines = ["\(indent)var \(variableName): JSONDictionary = [:]"]
        for parameter in parameters {
            let encodeCall = "try MCPClientArgumentEncoder.encode(\(parameter.name))"
            if parameter.isOptional {
                lines.append("\(indent)if let \(parameter.name) { \(variableName)[\"\(parameter.name)\"] = \(encodeCall) }")
            } else {
                lines.append("\(indent)\(variableName)[\"\(parameter.name)\"] = \(encodeCall)")
            }
        }
        return lines
    }

    static func blockDocCommentLines(_ bodyLines: [String], indent: String) -> [String] {
        guard !bodyLines.isEmpty else { return [] }
        var lines: [String] = []
        lines.append("\(indent)/**")
        for line in bodyLines {
            lines.append("\(indent) \(line)")
        }
        lines.append("\(indent) */")
        return lines
    }

}
