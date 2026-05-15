//
//  MCPExtensionMacro.swift
//  SwiftMCPMacros
//
//  Member macro for `@MCPExtension("Name") extension MyServer { ... }`.
//
//  Scans the extension body for `@MCPTool`, `@MCPResource`, and `@MCPPrompt`
//  functions, and emits a nested namespace enum named after the extension.
//  The enum carries metadata literals, typed dispatchers, and a
//  `register(in:)` entry point that pushes the contribution onto a server
//  instance.
//
//  The peer macros (`@MCPTool`, `@MCPResource`, `@MCPPrompt`) detect
//  extension context and skip emitting their stored metadata `let` (illegal
//  in extensions). Their wrapper functions are still emitted, and this
//  macro stitches them up.
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

        guard let extensionName = resolveExtensionName(node: node, decl: extDecl, context: context) else {
            return []
        }

        let extendedType = extDecl.extendedType.trimmedDescription
        let annotations = collectAnnotatedMembers(in: extDecl)

        let toolSection = try renderToolSection(
            toolFns: annotations.toolFns,
            extendedType: extendedType,
            context: context
        )
        let resourceSection = try renderResourceSection(
            resourceFns: annotations.resourceFns,
            extendedType: extendedType,
            context: context
        )
        let promptSection = try renderPromptSection(
            promptFns: annotations.promptFns,
            extendedType: extendedType,
            context: context
        )

        let initArgs = makeContributionInitArgs(annotations: annotations)
        let nestedEnum = """
public enum \(extensionName) {
\(toolSection)
\(resourceSection)
\(promptSection)
   /// Installs this extension's contributions on `server`. Idempotent —
   /// calling more than once with the same server has no effect.
   public static func register(in server: \(extendedType)) {
      server.__mcpRegisterExtension(
         MCPExtensionContribution(\(initArgs)),
         byID: ObjectIdentifier(Self.self)
      )
   }
}
"""

        return [DeclSyntax(stringLiteral: nestedEnum)]
    }

    /// Resolves the extension name from the attribute's first string-literal
    /// argument or, when absent, derives it from the source file path.
    private static func resolveExtensionName(
        node: AttributeSyntax,
        decl: ExtensionDeclSyntax,
        context: some MacroExpansionContext
    ) -> String? {
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self),
           let firstArg = arguments.first,
           let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self) {
            return stringLiteral.segments.description
        }
        return derivedExtensionName(from: context, of: decl)
    }

    struct AnnotatedMembers {
        var toolFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)] = []
        var resourceFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)] = []
        var promptFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)] = []
    }

    /// Walks the extension members and classifies each function by the MCP
    /// attribute it carries.
    private static func collectAnnotatedMembers(in extDecl: ExtensionDeclSyntax) -> AnnotatedMembers {
        var result = AnnotatedMembers()
        for member in extDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            for attr in funcDecl.attributes {
                guard let attrSyntax = attr.as(AttributeSyntax.self),
                      let id = attrSyntax.attributeName.as(IdentifierTypeSyntax.self) else { continue }
                switch id.name.text {
                case "MCPTool":     result.toolFns.append((funcDecl, attrSyntax))
                case "MCPResource": result.resourceFns.append((funcDecl, attrSyntax))
                case "MCPPrompt":   result.promptFns.append((funcDecl, attrSyntax))
                default: continue
                }
                break
            }
        }
        return result
    }

    private static func makeContributionInitArgs(annotations: AnnotatedMembers) -> String {
        var contributionInit: [String] = []
        if !annotations.toolFns.isEmpty {
            contributionInit.append("toolMetadata: toolMetadata")
            contributionInit.append("toolDispatcher: callTool")
        }
        if !annotations.resourceFns.isEmpty {
            contributionInit.append("resourceMetadata: resourceMetadata")
            contributionInit.append("resourceDispatcher: callResource")
        }
        if !annotations.promptFns.isEmpty {
            contributionInit.append("promptMetadata: promptMetadata")
            contributionInit.append("promptDispatcher: callPrompt")
        }
        if contributionInit.isEmpty { return "" }
        return "\n         " + contributionInit.joined(separator: ",\n         ") + "\n      "
    }

    // MARK: - Source-location-based name derivation

    /// When `@MCPExtension` is used without an explicit name, derive one
    /// from the source file. `MyServer+Calendar.swift` → `Calendar`. Any
    /// other file name gets its basename (minus `.swift`) sanitized into a
    /// valid Swift identifier.
    private static func derivedExtensionName(
        from context: some MacroExpansionContext,
        of decl: ExtensionDeclSyntax
    ) -> String? {
        guard let location = context.location(of: decl) else { return nil }
        guard let stringLit = location.file.as(StringLiteralExprSyntax.self) else { return nil }

        var path = ""
        for segment in stringLit.segments {
            if let stringSegment = segment.as(StringSegmentSyntax.self) {
                path.append(stringSegment.content.text)
            }
        }
        guard !path.isEmpty else { return nil }

        return MCPExtensionNaming.derive(from: path)
    }
}

/// Shared between the macro and (eventually) the build plugin tool so both
/// derive identical names from the same file paths.
enum MCPExtensionNaming {
    static func derive(from filePath: String) -> String {
        // Take the basename.
        let basename: String
        if let slashIdx = filePath.lastIndex(of: "/") {
            basename = String(filePath[filePath.index(after: slashIdx)...])
        } else {
            basename = filePath
        }

        // Strip a trailing .swift if present.
        var stem = basename
        if stem.hasSuffix(".swift") {
            stem = String(stem.dropLast(".swift".count))
        }

        // For "Foo+Bar" take only "Bar".
        if let plusIdx = stem.lastIndex(of: "+") {
            stem = String(stem[stem.index(after: plusIdx)...])
        }

        return sanitizeIdentifier(stem)
    }

    private static func sanitizeIdentifier(_ raw: String) -> String {
        guard !raw.isEmpty else { return "Extension" }
        var out = ""
        var first = true
        for character in raw {
            if first {
                if character.isLetter || character == "_" {
                    out.append(character)
                } else {
                    out.append("_")
                }
                first = false
            } else {
                if character.isLetter || character.isNumber || character == "_" {
                    out.append(character)
                } else {
                    out.append("_")
                }
            }
        }
        return out.isEmpty ? "Extension" : out
    }
}
