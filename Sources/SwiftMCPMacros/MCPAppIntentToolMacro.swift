//
//  MCPAppIntentToolMacro.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 19.03.25.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the MCPAppIntentTool macro.
public struct MCPAppIntentToolMacro: MemberMacro, ExtensionMacro {

    /// Arguments parsed from `@MCPAppIntentTool(...)`.
    struct AttributeArgs {
        var descriptionOverrideArg: String = "nil"
        var docDescriptionArg: String = "nil"
        var isConsequentialArg: String = "true"
        var hintsFromOptionSet: [String] = []
    }

    struct AppIntentParameter {
        let name: String
        let typeString: String
        let baseTypeString: String
        let defaultValueForMetadata: String
        let description: String?
        let isOptionalType: Bool

        func toMCPParameterInfo() -> String {
            let descriptionString = description ?? "nil"
            let isRequired = defaultValueForMetadata == "nil" && !isOptionalType
            return "MCPParameterInfo(name: \"\(name)\", type: \(baseTypeString).self, "
                + "description: \(descriptionString), "
                + "defaultValue: \(defaultValueForMetadata), "
                + "isRequired: \(isRequired))"
        }
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let typeName = typeName(from: declaration) else { return [] }
        guard isAppIntentDeclaration(declaration) else {
            let diagnostic = Diagnostic(
                node: Syntax(node),
                message: MCPToolDiagnostic.requiresAppIntentConformance(typeName: typeName)
            )
            context.diagnose(diagnostic)
            return []
        }

        let documentation = Documentation(from: declaration.leadingTrivia.description)
        var attrArgs = parseAttributeArguments(node: node)

        if !documentation.description.isEmpty {
            attrArgs.docDescriptionArg = "\"\(documentation.description.escapedForSwiftString)\""
        }

        let annotationsArg = makeAnnotationsArg(hints: attrArgs.hintsFromOptionSet)
        let parameters = appIntentParameters(from: declaration)
        let parameterInfoStrings = parameters.map { $0.toMCPParameterInfo() }
        let returnValueType = appIntentReturnValueType(from: declaration)
        let returnTypeExpression = returnValueType.map { "\($0).self" } ?? "Void.self"

        let metadataDeclaration = makeMetadataDeclaration(
            typeName: typeName,
            attrArgs: attrArgs,
            parameterInfoStrings: parameterInfoStrings,
            returnTypeExpression: returnTypeExpression,
            annotationsArg: annotationsArg
        )

        let performMethod = makePerformMethod(
            typeName: typeName,
            parameters: parameters,
            returnValueType: returnValueType
        )

        return [
            DeclSyntax(stringLiteral: metadataDeclaration),
            DeclSyntax(stringLiteral: performMethod)
        ]
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: node, providingMembersOf: declaration, in: context)
    }

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let inheritedTypes = declaration.inheritanceClause?.inheritedTypes ?? []
        let alreadyConforms = inheritedTypes.contains { type in
            type.type.trimmedDescription == "MCPAppIntentTool"
        }
        if alreadyConforms { return [] }

        let extensionDecl = try ExtensionDeclSyntax("extension \(type): MCPAppIntentTool {}")
        return [extensionDecl]
    }

    // MARK: - Attribute parsing

    private static func parseAttributeArguments(node: AttributeSyntax) -> AttributeArgs {
        var args = AttributeArgs()
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else { return args }
        for argument in arguments {
            guard let label = argument.label?.text else { continue }
            switch label {
            case "description":
                if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    let stringValue = stringLiteral.segments.description
                    args.descriptionOverrideArg = "\"\(stringValue.escapedForSwiftString)\""
                }
            case "hints":
                args.hintsFromOptionSet.append(contentsOf: parseHintsExpression(argument.expression))
            case "isConsequential":
                if let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                    args.isConsequentialArg = boolLiteral.literal.text
                }
            default:
                continue
            }
        }
        return args
    }

    private static func makeAnnotationsArg(hints: [String]) -> String {
        guard !hints.isEmpty else { return "nil" }
        let sortedHints = Set(hints).sorted()
        return "MCPToolAnnotations(hints: [\(sortedHints.joined(separator: ", "))])"
    }

    // MARK: - Emission

    private static func makeMetadataDeclaration(
        typeName: String,
        attrArgs: AttributeArgs,
        parameterInfoStrings: [String],
        returnTypeExpression: String,
        annotationsArg: String
    ) -> String {
        return """
/// Metadata for the \(typeName) tool
public static let mcpToolMetadata: MCPToolMetadata = {
   let descriptionOverride: String? = \(attrArgs.descriptionOverrideArg)
   let docDescription: String? = \(attrArgs.docDescriptionArg)
   let resolvedDescription = descriptionOverride ?? MCPAppIntentTools.descriptionText(for: Self.self) ?? docDescription
   return MCPToolMetadata(
      name: "\(typeName)",
      description: resolvedDescription,
      parameters: [\(parameterInfoStrings.joined(separator: ", "))],
      returnType: \(returnTypeExpression),
      returnTypeDescription: nil,
      isAsync: true,
      isThrowing: true,
      isConsequential: \(attrArgs.isConsequentialArg),
      annotations: \(annotationsArg)
   )
}()
"""
    }

    private static func makePerformMethod(
        typeName: String,
        parameters: [AppIntentParameter],
        returnValueType: String?
    ) -> String {
        var performMethod = """

/// Autogenerated AppIntent wrapper for \(typeName)
public static func mcpPerform(arguments: JSONDictionary) async throws -> (Encodable & Sendable) {
   let intent = Self()
"""

        for param in parameters {
            performMethod += """

   intent.\(param.name) = try arguments.extractValue(named: "\(param.name)", as: \(param.typeString).self)
"""
        }

        if let returnValueType {
            performMethod += """

   let result = try await intent.perform()
   if let value: \(returnValueType) = MCPAppIntentTools.extractReturnValue(
      from: result,
      as: \(returnValueType).self
   ) {
      return value
   }
   return ""
}
"""
        } else {
            performMethod += """

   _ = try await intent.perform()
   return ""
}
"""
        }

        return performMethod
    }
}
