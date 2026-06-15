//
//  MCPServerMacro+Helpers.swift
//  SwiftMCPMacros
//
//  Parses `@MCPServer` arguments and discovers tool / resource / prompt
//  functions on the annotated declaration.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

extension MCPServerMacro {
    struct ServerArguments {
        let name: String
        let version: String
        let descriptionLiteral: String
        let serverDescriptionText: String?
        let titleLiteral: String
        let websiteUrlLiteral: String
        let generateClient: Bool
        let toolNaming: String?
    }

    static func parseServerArguments(
        node: AttributeSyntax,
        declaration: some DeclGroupSyntax
    ) -> ServerArguments {
        let arguments = node.arguments?.as(LabeledExprListSyntax.self)
        let nameArg = arguments?
            .first(where: { $0.label?.text == "name" })?
            .expression.description
            .trimmingCharacters(in: .punctuationCharacters)
        let versionArg = arguments?
            .first(where: { $0.label?.text == "version" })?
            .expression.description
            .trimmingCharacters(in: .punctuationCharacters)

        let parsed = parseLabeledArguments(arguments)

        let serverName = nameArg
            ?? declaration.as(ClassDeclSyntax.self)?.name.text
            ?? declaration.as(StructDeclSyntax.self)?.name.text
            ?? "UnnamedServer"

        let serverVersion = versionArg ?? "1.0"

        // Extract description from leading documentation and allow override via macro argument
        let documentation = Documentation(from: declaration.leadingTrivia.description)
        var serverDescriptionText = parsed.serverDescriptionText
        if serverDescriptionText == nil, !documentation.description.isEmpty {
            serverDescriptionText = documentation.description
        }

        let serverDescription = resolveDescriptionLiteral(
            descriptionArg: parsed.descriptionArg,
            documentation: documentation
        )

        return ServerArguments(
            name: serverName,
            version: serverVersion,
            descriptionLiteral: serverDescription,
            serverDescriptionText: serverDescriptionText,
            titleLiteral: parsed.titleArg ?? "nil",
            websiteUrlLiteral: parsed.websiteUrlArg ?? "nil",
            generateClient: parsed.generateClient,
            toolNaming: parsed.toolNaming
        )
    }

    private struct ParsedLabeledArguments {
        var descriptionArg: String?
        var serverDescriptionText: String?
        var titleArg: String?
        var websiteUrlArg: String?
        var generateClient = false
        var toolNaming: String?
    }

    private static func parseLabeledArguments(_ arguments: LabeledExprListSyntax?) -> ParsedLabeledArguments {
        var parsed = ParsedLabeledArguments()
        guard let arguments else { return parsed }
        for argument in arguments {
            if argument.label?.text == "description",
               let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                let stringValue = stringLiteral.segments.description
                parsed.descriptionArg = "\"\(stringValue.escapedForSwiftString)\""
                parsed.serverDescriptionText = stringValue
            } else if argument.label?.text == "title",
                      let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                parsed.titleArg = "\"\(stringLiteral.segments.description.escapedForSwiftString)\""
            } else if argument.label?.text == "websiteUrl",
                      let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                parsed.websiteUrlArg = "\"\(stringLiteral.segments.description.escapedForSwiftString)\""
            } else if argument.label?.text == "generateClient",
                      let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                parsed.generateClient = boolLiteral.literal.text == "true"
            } else if argument.label?.text == "toolNaming",
                      let memberAccess = argument.expression.as(MemberAccessExprSyntax.self) {
                let convention = memberAccess.declName.baseName.text
                if convention != "functionName" {
                    parsed.toolNaming = convention
                }
            }
        }
        return parsed
    }

    private static func resolveDescriptionLiteral(
        descriptionArg: String?,
        documentation: Documentation
    ) -> String {
        if let descriptionArg {
            return descriptionArg
        }
        if documentation.description.isEmpty {
            return "nil"
        }
        return "\"\(documentation.description.escapedForSwiftString)\""
    }

    static func hasAppShortcutsProvider(declaration: some DeclGroupSyntax) -> Bool {
        let inheritedTypes = declaration.inheritanceClause?.inheritedTypes ?? []
        return inheritedTypes.contains { type in
            let name = type.type.trimmedDescription
            return name == "AppShortcutsProvider" || name.hasSuffix(".AppShortcutsProvider")
        }
    }

    static func collectToolFunctions(
        declaration: some DeclGroupSyntax,
        toolNaming: String?
    ) -> (mcpTools: [(functionName: String, toolName: String)], toolFunctions: [FunctionDeclSyntax]) {
        var mcpTools: [(functionName: String, toolName: String)] = []
        var toolFunctions: [FunctionDeclSyntax] = []

        for member in declaration.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            guard let identifierAttr = mcpAttribute(named: "MCPTool", on: funcDecl) else { continue }

            let functionName = funcDecl.name.text
            let finalToolName = resolveToolName(
                functionName: functionName,
                identifierAttr: identifierAttr,
                toolNaming: toolNaming
            )
            mcpTools.append((functionName: functionName, toolName: finalToolName))
            toolFunctions.append(funcDecl)
        }

        return (mcpTools, toolFunctions)
    }

    static func resolveToolName(
        functionName: String,
        identifierAttr: AttributeSyntax,
        toolNaming: String?
    ) -> String {
        // Check for name: override in @MCPTool arguments
        var toolName = functionName
        if let arguments = identifierAttr.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments where argument.label?.text == "name" {
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    toolName = stringLiteral.segments.description
                    break
                }
            }
        }
        // Apply server-level toolNaming if no explicit name: override
        let hasExplicitName = toolName != functionName
        if hasExplicitName {
            return toolName
        }
        guard let toolNaming else { return functionName }
        switch toolNaming {
        case "snakeCase":
            return ToolNamingConverter.toSnakeCase(functionName)
        case "pascalCase":
            return ToolNamingConverter.toPascalCase(functionName)
        default:
            return functionName
        }
    }

    static func collectResourceFunctions(
        declaration: some DeclGroupSyntax
    ) -> (mcpResources: [String], resourceFunctions: [FunctionDeclSyntax]) {
        var mcpResources: [String] = []
        var resourceFunctions: [FunctionDeclSyntax] = []

        for member in declaration.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            if mcpAttribute(named: "MCPResource", on: funcDecl) != nil {
                mcpResources.append(funcDecl.name.text)
                resourceFunctions.append(funcDecl)
            }
        }

        return (mcpResources, resourceFunctions)
    }

    static func collectPromptFunctions(
        declaration: some DeclGroupSyntax
    ) -> (mcpPrompts: [String], promptFunctions: [FunctionDeclSyntax]) {
        var mcpPrompts: [String] = []
        var promptFunctions: [FunctionDeclSyntax] = []

        for member in declaration.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            if mcpAttribute(named: "MCPPrompt", on: funcDecl) != nil {
                mcpPrompts.append(funcDecl.name.text)
                promptFunctions.append(funcDecl)
            }
        }

        return (mcpPrompts, promptFunctions)
    }

    static func mcpAttribute(named name: String, on funcDecl: FunctionDeclSyntax) -> AttributeSyntax? {
        for attribute in funcDecl.attributes {
            if let identifierAttr = attribute.as(AttributeSyntax.self),
               let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
               identifier.name.text == name {
                return identifierAttr
            }
        }
        return nil
    }

    static func declarationHasMCPAttribute(
        named name: String,
        on declaration: some DeclGroupSyntax
    ) -> Bool {
        for member in declaration.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            if mcpAttribute(named: name, on: funcDecl) != nil {
                return true
            }
        }
        return false
    }
}
