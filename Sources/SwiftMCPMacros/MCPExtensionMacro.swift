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

        // Name is optional; if absent, derive from the source file name.
        // For "MyServer+Calendar.swift" → "Calendar"; for any other file
        // name, sanitize the basename (without extension) into a valid
        // Swift identifier.
        var extensionName: String? = nil
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self),
           let firstArg = arguments.first,
           let stringLiteral = firstArg.expression.as(StringLiteralExprSyntax.self) {
            extensionName = stringLiteral.segments.description
        }

        if extensionName == nil {
            extensionName = derivedExtensionName(from: context, of: extDecl)
        }

        guard let extensionName else {
            // No name supplied and source location unavailable — bail out.
            return []
        }

        let extendedType = extDecl.extendedType.trimmedDescription

        // ---------- collect annotated members ----------
        var toolFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)] = []
        var resourceFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)] = []
        var promptFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)] = []

        for member in extDecl.memberBlock.members {
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { continue }
            for attr in funcDecl.attributes {
                guard let attrSyntax = attr.as(AttributeSyntax.self),
                      let id = attrSyntax.attributeName.as(IdentifierTypeSyntax.self) else { continue }
                switch id.name.text {
                case "MCPTool":     toolFns.append((funcDecl, attrSyntax))
                case "MCPResource": resourceFns.append((funcDecl, attrSyntax))
                case "MCPPrompt":   promptFns.append((funcDecl, attrSyntax))
                default: continue
                }
                break
            }
        }

        // ---------- generate per-kind sections ----------
        let toolSection = try renderToolSection(
            toolFns: toolFns,
            extendedType: extendedType,
            context: context
        )
        let resourceSection = try renderResourceSection(
            resourceFns: resourceFns,
            extendedType: extendedType,
            context: context
        )
        let promptSection = try renderPromptSection(
            promptFns: promptFns,
            extendedType: extendedType,
            context: context
        )

        // ---------- emit nested enum ----------
        var contributionInit: [String] = []
        if !toolFns.isEmpty {
            contributionInit.append("toolMetadata: toolMetadata")
            contributionInit.append("toolDispatcher: callTool")
        }
        if !resourceFns.isEmpty {
            contributionInit.append("resourceMetadata: resourceMetadata")
            contributionInit.append("resourceDispatcher: callResource")
        }
        if !promptFns.isEmpty {
            contributionInit.append("promptMetadata: promptMetadata")
            contributionInit.append("promptDispatcher: callPrompt")
        }

        let initArgs = contributionInit.isEmpty
            ? ""
            : "\n         " + contributionInit.joined(separator: ",\n         ") + "\n      "

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

    // MARK: - Tool section

    private static func renderToolSection(
        toolFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)],
        extendedType: String,
        context: some MacroExpansionContext
    ) throws -> String {
        guard !toolFns.isEmpty else { return "" }

        var literals: [String] = []
        var cases: [String] = []

        for (funcDecl, attribute) in toolFns {
            let extractor = FunctionMetadataExtractor(funcDecl: funcDecl, context: context)
            let extracted = try extractor.extract()
            let toolArgs = parseToolArgs(attribute: attribute, defaults: extracted)

            literals.append("""
MCPToolMetadata(
   name: "\(toolArgs.wireName)",
   description: \(toolArgs.descriptionArg),
   parameters: [\(extracted.parameters.map { $0.toMCPParameterInfo() }.joined(separator: ", "))],
   returnType: \(extracted.returnTypeString).self,
   returnTypeDescription: \(extracted.returnDescription ?? "nil"),
   isAsync: \(extracted.isAsync),
   isThrowing: \(extracted.isThrowing),
   isConsequential: \(toolArgs.isConsequential),
   annotations: \(toolArgs.annotationsArg)
)
""")
            cases.append("""
      case "\(toolArgs.wireName)":
         return try await server.__mcpCall_\(extracted.functionName)(arguments)
""")
        }

        return """

   public static let toolMetadata: [MCPToolMetadata] = [
      \(literals.joined(separator: ",\n      "))
   ]

   public static func callTool(
      _ name: String,
      on server: \(extendedType),
      arguments: JSONDictionary
   ) async throws -> Encodable & Sendable {
      switch name {
\(cases.joined(separator: "\n"))
      default:
         throw MCPToolError.unknownTool(name: name)
      }
   }
"""
    }

    // MARK: - Resource section

    private static func renderResourceSection(
        resourceFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)],
        extendedType: String,
        context: some MacroExpansionContext
    ) throws -> String {
        guard !resourceFns.isEmpty else { return "" }

        var literals: [String] = []
        var cases: [String] = []

        for (funcDecl, attribute) in resourceFns {
            let extractor = FunctionMetadataExtractor(funcDecl: funcDecl, context: context)
            let extracted = try extractor.extract()
            let res = parseResourceArgs(attribute: attribute, defaults: extracted)

            let templatesSet = "[\(res.templates.map { "\"\($0)\"" }.joined(separator: ", "))]"

            literals.append("""
MCPResourceMetadata(
   uriTemplates: Set(\(templatesSet)),
   name: "\(res.resourceName)",
   functionName: "\(extracted.functionName)",
   description: \(res.descriptionArg),
   parameters: [\(extracted.parameters.map { $0.toMCPParameterInfo() }.joined(separator: ", "))],
   returnType: \(extracted.returnTypeString).self,
   returnTypeDescription: \(extracted.returnDescription ?? "nil"),
   isAsync: \(extracted.isAsync),
   isThrowing: \(extracted.isThrowing),
   mimeType: \(res.mimeTypeArg)
)
""")
            cases.append("""
      case "\(extracted.functionName)":
         return try await server.__mcpResourceCall_\(extracted.functionName)(arguments, requestedUri: requestedUri, overrideMimeType: overrideMimeType)
""")
        }

        return """

   public static let resourceMetadata: [MCPResourceMetadata] = [
      \(literals.joined(separator: ",\n      "))
   ]

   public static func callResource(
      _ name: String,
      on server: \(extendedType),
      arguments: JSONDictionary,
      requestedUri: URL,
      overrideMimeType: String?
   ) async throws -> [MCPResourceContent] {
      switch name {
\(cases.joined(separator: "\n"))
      default:
         throw MCPResourceError.notFound(uri: requestedUri.absoluteString)
      }
   }
"""
    }

    // MARK: - Prompt section

    private static func renderPromptSection(
        promptFns: [(funcDecl: FunctionDeclSyntax, attribute: AttributeSyntax)],
        extendedType: String,
        context: some MacroExpansionContext
    ) throws -> String {
        guard !promptFns.isEmpty else { return "" }

        var literals: [String] = []
        var cases: [String] = []

        for (funcDecl, attribute) in promptFns {
            let extractor = FunctionMetadataExtractor(funcDecl: funcDecl, context: context)
            let extracted = try extractor.extract()
            let descriptionArg = parsePromptDescription(attribute: attribute, defaults: extracted)

            literals.append("""
MCPPromptMetadata(
   name: "\(extracted.functionName)",
   description: \(descriptionArg),
   parameters: [\(extracted.parameters.map { $0.toMCPParameterInfo() }.joined(separator: ", "))],
   isAsync: \(extracted.isAsync),
   isThrowing: \(extracted.isThrowing)
)
""")
            cases.append("""
      case "\(extracted.functionName)":
         return try await server.__mcpPromptCall_\(extracted.functionName)(arguments)
""")
        }

        return """

   public static let promptMetadata: [MCPPromptMetadata] = [
      \(literals.joined(separator: ",\n      "))
   ]

   public static func callPrompt(
      _ name: String,
      on server: \(extendedType),
      arguments: JSONDictionary
   ) async throws -> [PromptMessage] {
      switch name {
\(cases.joined(separator: "\n"))
      default:
         throw MCPToolError.unknownTool(name: name)
      }
   }
"""
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
            if let s = segment.as(StringSegmentSyntax.self) {
                path.append(s.content.text)
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

    private static func sanitizeIdentifier(_ s: String) -> String {
        guard !s.isEmpty else { return "Extension" }
        var out = ""
        var first = true
        for ch in s {
            if first {
                if ch.isLetter || ch == "_" {
                    out.append(ch)
                } else {
                    out.append("_")
                }
                first = false
            } else {
                if ch.isLetter || ch.isNumber || ch == "_" {
                    out.append(ch)
                } else {
                    out.append("_")
                }
            }
        }
        return out.isEmpty ? "Extension" : out
    }
}

extension MCPExtensionMacro {
    // MARK: - Argument parsers (shared logic with the per-kind macros)

    private struct ToolArgs {
        var wireName: String
        var descriptionArg: String
        var isConsequential: String
        var annotationsArg: String
    }

    private static func parseToolArgs(attribute: AttributeSyntax, defaults: ExtractedFunctionMetadata) -> ToolArgs {
        var wireName = defaults.functionName
        var descriptionArg = "nil"
        var isConsequentialArg = "true"

        var hintsFromOptionSet: [String] = []
        var readOnlyHintArg: String? = nil
        var destructiveHintArg: String? = nil
        var idempotentHintArg: String? = nil
        var openWorldHintArg: String? = nil

        if let argList = attribute.arguments?.as(LabeledExprListSyntax.self) {
            for arg in argList {
                guard let label = arg.label?.text else { continue }
                switch label {
                case "name":
                    if let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                        wireName = lit.segments.description
                    }
                case "description":
                    if let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                        descriptionArg = "\"\(lit.segments.description.escapedForSwiftString)\""
                    }
                case "hints":
                    if let arr = arg.expression.as(ArrayExprSyntax.self) {
                        for element in arr.elements {
                            if let memberAccess = element.expression.as(MemberAccessExprSyntax.self) {
                                hintsFromOptionSet.append(".\(memberAccess.declName.baseName.text)")
                            }
                        }
                    }
                case "isConsequential":
                    if let lit = arg.expression.as(BooleanLiteralExprSyntax.self) {
                        isConsequentialArg = lit.literal.text
                    }
                case "readOnlyHint":
                    if let lit = arg.expression.as(BooleanLiteralExprSyntax.self) { readOnlyHintArg = lit.literal.text }
                case "destructiveHint":
                    if let lit = arg.expression.as(BooleanLiteralExprSyntax.self) { destructiveHintArg = lit.literal.text }
                case "idempotentHint":
                    if let lit = arg.expression.as(BooleanLiteralExprSyntax.self) { idempotentHintArg = lit.literal.text }
                case "openWorldHint":
                    if let lit = arg.expression.as(BooleanLiteralExprSyntax.self) { openWorldHintArg = lit.literal.text }
                default: continue
                }
            }
        }

        if descriptionArg == "nil", !defaults.documentation.description.isEmpty {
            descriptionArg = "\"\(defaults.documentation.description.escapedForSwiftString)\""
        }

        var allHints = Set(hintsFromOptionSet)
        if readOnlyHintArg == "true"   { allHints.insert(".readOnly") }
        if destructiveHintArg == "true" { allHints.insert(".destructive") }
        if idempotentHintArg == "true"  { allHints.insert(".idempotent") }
        if openWorldHintArg == "true"   { allHints.insert(".openWorld") }

        let annotationsArg: String
        if allHints.isEmpty {
            annotationsArg = "nil"
        } else {
            annotationsArg = "MCPToolAnnotations(hints: [\(allHints.sorted().joined(separator: ", "))])"
        }

        return ToolArgs(
            wireName: wireName,
            descriptionArg: descriptionArg,
            isConsequential: isConsequentialArg,
            annotationsArg: annotationsArg
        )
    }

    private struct ResourceArgs {
        var templates: [String]
        var resourceName: String
        var descriptionArg: String
        var mimeTypeArg: String
    }

    private static func parseResourceArgs(attribute: AttributeSyntax, defaults: ExtractedFunctionMetadata) -> ResourceArgs {
        var templates: [String] = []
        var resourceName = defaults.functionName
        var descriptionArg = "nil"
        var mimeTypeArg = "nil"

        if let argList = attribute.arguments?.as(LabeledExprListSyntax.self) {
            for arg in argList {
                if arg.label == nil {
                    if let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                        templates.append(lit.segments.description)
                    } else if let arr = arg.expression.as(ArrayExprSyntax.self) {
                        for element in arr.elements {
                            if let lit = element.expression.as(StringLiteralExprSyntax.self) {
                                templates.append(lit.segments.description)
                            }
                        }
                    }
                    continue
                }
                switch arg.label?.text {
                case "name":
                    if let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                        resourceName = lit.segments.description
                    }
                case "mimeType":
                    if let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                        mimeTypeArg = "\"\(lit.segments.description.escapedForSwiftString)\""
                    }
                default: continue
                }
            }
        }

        if descriptionArg == "nil", !defaults.documentation.description.isEmpty {
            descriptionArg = "\"\(defaults.documentation.description.escapedForSwiftString)\""
        }

        return ResourceArgs(
            templates: templates,
            resourceName: resourceName,
            descriptionArg: descriptionArg,
            mimeTypeArg: mimeTypeArg
        )
    }

    private static func parsePromptDescription(attribute: AttributeSyntax, defaults: ExtractedFunctionMetadata) -> String {
        var descriptionArg = "nil"
        if let argList = attribute.arguments?.as(LabeledExprListSyntax.self) {
            for arg in argList where arg.label?.text == "description" {
                if let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                    descriptionArg = "\"\(lit.segments.description.escapedForSwiftString)\""
                }
            }
        }
        if descriptionArg == "nil", !defaults.documentation.description.isEmpty {
            descriptionArg = "\"\(defaults.documentation.description.escapedForSwiftString)\""
        }
        return descriptionArg
    }
}
