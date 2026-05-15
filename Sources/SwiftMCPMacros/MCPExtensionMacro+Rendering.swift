//
//  MCPExtensionMacro+Rendering.swift
//  SwiftMCPMacros
//
//  Per-kind rendering (tool / resource / prompt) for the nested namespace
//  enum emitted by `@MCPExtension`.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

extension MCPExtensionMacro {
    // MARK: - Tool section

    static func renderToolSection(
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

    static func renderResourceSection(
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
            literals.append(renderResourceLiteral(res: res, extracted: extracted))
            cases.append(renderResourceCase(extracted: extracted))
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

    private static func renderResourceLiteral(
        res: ResourceArgs,
        extracted: ExtractedFunctionMetadata
    ) -> String {
        let templatesSet = "[\(res.templates.map { "\"\($0)\"" }.joined(separator: ", "))]"
        let paramInfoList = extracted.parameters.map { $0.toMCPParameterInfo() }.joined(separator: ", ")
        return """
MCPResourceMetadata(
   uriTemplates: Set(\(templatesSet)),
   name: "\(res.resourceName)",
   functionName: "\(extracted.functionName)",
   description: \(res.descriptionArg),
   parameters: [\(paramInfoList)],
   returnType: \(extracted.returnTypeString).self,
   returnTypeDescription: \(extracted.returnDescription ?? "nil"),
   isAsync: \(extracted.isAsync),
   isThrowing: \(extracted.isThrowing),
   mimeType: \(res.mimeTypeArg)
)
"""
    }

    private static func renderResourceCase(extracted: ExtractedFunctionMetadata) -> String {
        return """
      case "\(extracted.functionName)":
         return try await server.__mcpResourceCall_\(extracted.functionName)(
            arguments,
            requestedUri: requestedUri,
            overrideMimeType: overrideMimeType
         )
"""
    }

    // MARK: - Prompt section

    static func renderPromptSection(
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
}
