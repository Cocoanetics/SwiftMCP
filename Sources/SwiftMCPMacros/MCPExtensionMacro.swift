//
//  MCPExtensionMacro.swift
//  SwiftMCPMacros
//
//  Member macro for `@MCPExtension("Name") extension MyServer { ... }`.
//
//  Scans the extension body for `@MCPExtensionTool` functions and emits a
//  nested namespace enum named after the extension. The enum carries the
//  metadata literal, the typed dispatcher, and a `register(in:)` entry
//  point that pushes the contribution onto a server instance.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

public struct MCPExtensionMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let extDecl = declaration.as(ExtensionDeclSyntax.self) else {
            return []
        }

        // Extract the extension's name (the macro's only positional argument).
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self),
              let firstArg = arguments.first,
              let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self) else {
            return []
        }
        let extensionName = stringLiteral.segments.description

        let extendedType = extDecl.extendedType.trimmedDescription

        // Collect functions annotated with `@MCPExtensionTool`.
        var tools: [(funcDecl: FunctionDeclSyntax, wireName: String)] = []
        for member in extDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            for attr in funcDecl.attributes {
                guard let attrSyntax = attr.as(AttributeSyntax.self),
                      let id = attrSyntax.attributeName.as(IdentifierTypeSyntax.self),
                      id.name.text == "MCPExtensionTool" else { continue }

                var wireName = funcDecl.name.text
                if let argList = attrSyntax.arguments?.as(LabeledExprListSyntax.self) {
                    for a in argList where a.label?.text == "name" {
                        if let lit = a.expression.as(StringLiteralExprSyntax.self) {
                            wireName = lit.segments.description
                        }
                    }
                }
                tools.append((funcDecl, wireName))
                break
            }
        }

        // Build metadata literals + switch cases.
        var metadataLiterals: [String] = []
        var switchCases: [String] = []

        for (funcDecl, wireName) in tools {
            let extractor = FunctionMetadataExtractor(funcDecl: funcDecl, context: context)
            let extracted = try extractor.extract()

            // Description from doc, plus per-tool override.
            var descriptionArg = "nil"
            if !extracted.documentation.description.isEmpty {
                descriptionArg = "\"\(extracted.documentation.description.escapedForSwiftString)\""
            }
            for attr in funcDecl.attributes {
                guard let attrSyntax = attr.as(AttributeSyntax.self),
                      let id = attrSyntax.attributeName.as(IdentifierTypeSyntax.self),
                      id.name.text == "MCPExtensionTool",
                      let argList = attrSyntax.arguments?.as(LabeledExprListSyntax.self) else { continue }
                for a in argList where a.label?.text == "description" {
                    if let lit = a.expression.as(StringLiteralExprSyntax.self) {
                        descriptionArg = "\"\(lit.segments.description.escapedForSwiftString)\""
                    }
                }
            }

            let parameterInfos = extracted.parameters.map { $0.toMCPParameterInfo() }.joined(separator: ", ")
            let returnDescription = extracted.returnDescription ?? "nil"

            let literal = """
MCPToolMetadata(
   name: "\(wireName)",
   description: \(descriptionArg),
   parameters: [\(parameterInfos)],
   returnType: \(extracted.returnTypeString).self,
   returnTypeDescription: \(returnDescription),
   isAsync: \(extracted.isAsync),
   isThrowing: \(extracted.isThrowing),
   isConsequential: true,
   annotations: nil
)
"""
            metadataLiterals.append(literal)

            switchCases.append("""
      case "\(wireName)":
         return try await server.__mcpCall_\(extracted.functionName)(arguments)
""")
        }

        let metadataArrayBody = metadataLiterals.isEmpty
            ? "[]"
            : "[\n   " + metadataLiterals.joined(separator: ",\n   ") + "\n]"

        let switchBody = switchCases.isEmpty
            ? "      default: throw MCPToolError.unknownTool(name: name)"
            : switchCases.joined(separator: "\n") + """

      default:
         throw MCPToolError.unknownTool(name: name)
"""

        // Emit the nested enum. Member macros on extensions place this inside
        // the extension's body, which means it becomes a nested type on the
        // extended type — `MyServer.<extensionName>`.
        let nestedEnum = """
public enum \(extensionName) {
   public static let toolMetadata: [MCPToolMetadata] = \(metadataArrayBody)

   public static func callTool(
      _ name: String,
      on server: \(extendedType),
      arguments: JSONDictionary
   ) async throws -> Encodable & Sendable {
      switch name {
\(switchBody)
      }
   }

   public static func register(in server: \(extendedType)) {
      server.__mcpRegisterExtension(MCPExtensionContribution(
         metadata: toolMetadata,
         dispatcher: callTool
      ))
   }
}
"""

        return [DeclSyntax(stringLiteral: nestedEnum)]
    }
}
