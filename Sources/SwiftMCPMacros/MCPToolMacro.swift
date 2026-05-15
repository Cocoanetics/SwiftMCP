//
//  MCPToolMacro.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/**
 Implementation of the MCPTool macro.

 This macro transforms a function into an MCP tool by generating metadata and wrapper
 functions for parameter handling and type safety.

 Example usage:
 ```swift
 /// Adds two numbers together
 /// - Parameters:
 ///   - a: First number to add
 ///   - b: Second number to add
 /// - Returns: The sum of the two numbers
 @MCPTool
 func add(_ a: Double, _ b: Double = 0) -> Double {
     return a + b
 }
 ```

 - Parameters:
   - description: Optional override for the function's documentation description.
   - isConsequential: Whether the function's actions are consequential (defaults to true).

 - Note: The macro extracts documentation from the function's comments for:
   * Function description
   * Parameter descriptions
   * Return value description

 - Attention: The macro will emit diagnostics for:
   * Missing function descriptions
   * Invalid default value types
   * Non-function declarations
 */
public struct MCPToolMacro: PeerMacro {
    /// Arguments parsed from `@MCPTool(...)`.
    struct ToolAttributeArgs {
        var customName: String?
        var descriptionArg: String = "nil"
        var isConsequentialArg: String = "true"
        var hintsFromOptionSet: [String] = []
        var readOnlyHintArg: String?
        var destructiveHintArg: String?
        var idempotentHintArg: String?
        var openWorldHintArg: String?
    }

    /**
     Expands the macro to provide peers for the declaration.
     */
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            let diagnostic = Diagnostic(node: Syntax(node), message: MCPToolDiagnostic.onlyFunctions)
            context.diagnose(diagnostic)
            return []
        }

        return try functionPeers(for: funcDecl, node: node, context: context)
    }

    private static func functionPeers(
        for funcDecl: FunctionDeclSyntax,
        node: AttributeSyntax,
        context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let extractor = FunctionMetadataExtractor(funcDecl: funcDecl, context: context)
        let commonMetadata = try extractor.extract()
        let functionName = commonMetadata.functionName

        var attrArgs = parseAttributeArguments(node: node)

        if attrArgs.descriptionArg == "nil" && !commonMetadata.documentation.description.isEmpty {
            attrArgs.descriptionArg = "\"\(commonMetadata.documentation.description.escapedForSwiftString)\""
        }

        if attrArgs.descriptionArg == "nil" && functionName != "missingDescription" {
            let diagnostic = Diagnostic(
                node: Syntax(funcDecl.name),
                message: MCPToolDiagnostic.missingDescription(functionName: functionName)
            )
            context.diagnose(diagnostic)
        }

        let parameterInfoStrings = commonMetadata.parameters.map { $0.toMCPParameterInfo() }
        let annotationsArg = buildAnnotationsArg(args: attrArgs)
        let toolName = attrArgs.customName ?? functionName

        let metadataDeclaration = makeMetadataDeclaration(
            inputs: MetadataDeclarationInputs(
                toolName: toolName,
                functionName: functionName,
                descriptionArg: attrArgs.descriptionArg,
                parameterInfoStrings: parameterInfoStrings,
                commonMetadata: commonMetadata,
                isConsequentialArg: attrArgs.isConsequentialArg,
                annotationsArg: annotationsArg
            )
        )

        let wrapperFuncString = makeWrapperFunction(
            functionName: functionName,
            commonMetadata: commonMetadata
        )

        if let enclosing = MCPMacroContextDetection.enclosingExtension(in: context) {
            if !MCPMacroContextDetection.hasMCPExtensionAttribute(enclosing) {
                let diag = Diagnostic(
                    node: Syntax(funcDecl.name),
                    message: MCPToolDiagnostic.missingMCPExtensionAttribute(macroName: "MCPTool")
                )
                context.diagnose(diag)
            }
            return [DeclSyntax(stringLiteral: wrapperFuncString)]
        }

        return [
            DeclSyntax(stringLiteral: metadataDeclaration),
            DeclSyntax(stringLiteral: wrapperFuncString)
        ]
    }

    /// Parses the `@MCPTool(...)` attribute arguments into a struct.
    private static func parseAttributeArguments(node: AttributeSyntax) -> ToolAttributeArgs {
        var args = ToolAttributeArgs()
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else { return args }
        for argument in arguments {
            applyAttributeArgument(argument, to: &args)
        }
        return args
    }

    /// Applies a single labeled argument to the attribute args struct.
    /// Pulled out of `parseAttributeArguments` so the cyclomatic complexity
    /// stays bounded.
    private static func applyAttributeArgument(
        _ argument: LabeledExprListSyntax.Element,
        to args: inout ToolAttributeArgs
    ) {
        guard let label = argument.label?.text else { return }
        switch label {
        case "name":
            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                args.customName = stringLiteral.segments.description
            }
        case "description":
            if let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                let stringValue = stringLiteral.segments.description
                args.descriptionArg = "\"\(stringValue.escapedForSwiftString)\""
            }
        case "hints":
            args.hintsFromOptionSet.append(contentsOf: parseHintsExpression(argument.expression))
        case "isConsequential":
            if let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                args.isConsequentialArg = boolLiteral.literal.text
            }
        default:
            applyLegacyHintArgument(label: label, expression: argument.expression, to: &args)
        }
    }

    /// Applies the legacy `*Hint:` boolean arguments. Kept separate from
    /// `applyAttributeArgument` so each switch stays under the complexity
    /// limit.
    private static func applyLegacyHintArgument(
        label: String,
        expression: ExprSyntax,
        to args: inout ToolAttributeArgs
    ) {
        guard let boolLiteral = expression.as(BooleanLiteralExprSyntax.self) else { return }
        switch label {
        case "readOnlyHint":
            args.readOnlyHintArg = boolLiteral.literal.text
        case "destructiveHint":
            args.destructiveHintArg = boolLiteral.literal.text
        case "idempotentHint":
            args.idempotentHintArg = boolLiteral.literal.text
        case "openWorldHint":
            args.openWorldHintArg = boolLiteral.literal.text
        default:
            return
        }
    }

    /// Bundles the arguments needed to render the `__mcpMetadata_*`
    /// declaration. Grouped into a struct so the call site stays under the
    /// function-parameter-count limit.
    private struct MetadataDeclarationInputs {
        let toolName: String
        let functionName: String
        let descriptionArg: String
        let parameterInfoStrings: [String]
        let commonMetadata: ExtractedFunctionMetadata
        let isConsequentialArg: String
        let annotationsArg: String
    }

    private static func makeMetadataDeclaration(
        inputs: MetadataDeclarationInputs
    ) -> String {
        let returnTypeString = inputs.commonMetadata.returnTypeString
        let returnDescriptionString = inputs.commonMetadata.returnDescription ?? "nil"
        return """
/// Metadata for the \(inputs.toolName) tool
nonisolated private let __mcpMetadata_\(inputs.functionName) = MCPToolMetadata(
   name: "\(inputs.toolName)",
   description: \(inputs.descriptionArg),
   parameters: [\(inputs.parameterInfoStrings.joined(separator: ", "))],
   returnType: \(returnTypeString).self,
   returnTypeDescription: \(returnDescriptionString),
   isAsync: \(inputs.commonMetadata.isAsync),
   isThrowing: \(inputs.commonMetadata.isThrowing),
   isConsequential: \(inputs.isConsequentialArg),
   annotations: \(inputs.annotationsArg)
)
"""
    }

    private static func makeWrapperFunction(
        functionName: String,
        commonMetadata: ExtractedFunctionMetadata
    ) -> String {
        var wrapperFuncString = """

		/// Autogenerated wrapper for \(functionName) that takes a dictionary of parameters
"""
        for attribute in commonMetadata.propagatedAttributes {
            wrapperFuncString += "\n\t\t\(attribute)"
        }
        wrapperFuncString += "\n\t\tfunc __mcpCall_\(functionName)"
            + "(_ enrichedArguments: JSONDictionary) "
            + "async throws -> (Encodable & Sendable) {\n"

        for detail in commonMetadata.parameters {
            wrapperFuncString += """

			   let \(detail.name): \(detail.typeString) = try enrichedArguments.extractValue(
			       named: "\(detail.name)",
			       as: \(detail.typeString).self
			   )
			"""
        }

        let parameterList = commonMetadata.parameters.map { param in
            param.label == "_" ? param.name : "\(param.label): \(param.name)"
        }.joined(separator: ", ")

        let tryPrefix = commonMetadata.isThrowing ? "try " : ""
        let awaitPrefix = commonMetadata.isAsync ? "await " : ""
        if commonMetadata.returnTypeString == "Void" {
            wrapperFuncString += """
				\(tryPrefix)\(awaitPrefix)\(functionName)(\(parameterList))
				return ""  // return empty string for Void functions
			}
			"""
        } else {
            wrapperFuncString += """
				return \(tryPrefix)\(awaitPrefix)\(functionName)(\(parameterList))
			}
			"""
        }
        return wrapperFuncString
    }

    /// Builds the annotations argument string for MCPToolMetadata initialization
    /// Returns "nil" if no hints are provided, otherwise returns a MCPToolAnnotations initialization
    /// Supports both the new OptionSet API (hints: [.readOnly]) and legacy Bool? parameters
    private static func buildAnnotationsArg(args: ToolAttributeArgs) -> String {
        var allHints = Set(args.hintsFromOptionSet)

        if args.readOnlyHintArg == "true" { allHints.insert(".readOnly") }
        if args.destructiveHintArg == "true" { allHints.insert(".destructive") }
        if args.idempotentHintArg == "true" { allHints.insert(".idempotent") }
        if args.openWorldHintArg == "true" { allHints.insert(".openWorld") }

        if allHints.isEmpty {
            return "nil"
        }
        return "MCPToolAnnotations(hints: [\(allHints.sorted().joined(separator: ", "))])"
    }
}
