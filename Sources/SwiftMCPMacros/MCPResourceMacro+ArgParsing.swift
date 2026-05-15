//
//  MCPResourceMacro+ArgParsing.swift
//  SwiftMCPMacros
//
//  Argument parsing and template/placeholder bookkeeping for `@MCPResource`.
//

import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

extension MCPResourceMacro {
    /// Parses the `@MCPResource(...)` attribute arguments. Returns nil when
    /// the attribute is malformed (the diagnostic has already been emitted).
    static func parseAttributeArguments(
        node: AttributeSyntax,
        functionName: String,
        context: some MacroExpansionContext
    ) -> ResourceAttributeArgs? {
        guard let argList = node.arguments?.as(LabeledExprListSyntax.self) else {
            let diag = Diagnostic(node: Syntax(node), message: MCPResourceDiagnostic.requiresStringLiteral)
            context.diagnose(diag)
            return nil
        }

        let templates = extractTemplates(from: argList)
        if templates.isEmpty {
            let diag = Diagnostic(node: Syntax(node), message: MCPResourceDiagnostic.requiresStringLiteral)
            context.diagnose(diag)
            return nil
        }

        var resourceName = functionName
        var mimeTypeArg = "nil"
        for argument in argList {
            guard let label = argument.label?.text else { continue }
            if label == "name", let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                resourceName = stringLiteral.segments.description
            } else if label == "mimeType", let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                let stringValue = stringLiteral.segments.description
                mimeTypeArg = "\"\(stringValue.escapedForSwiftString)\""
            }
        }

        return ResourceAttributeArgs(
            templates: templates,
            resourceName: resourceName,
            mimeTypeArg: mimeTypeArg
        )
    }

    private static func extractTemplates(from argList: LabeledExprListSyntax) -> [String] {
        var templates: [String] = []
        for arg in argList where arg.label == nil {
            if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self) {
                templates.append(stringLiteral.segments.description)
            } else if let arrayExpr = arg.expression.as(ArrayExprSyntax.self) {
                for element in arrayExpr.elements {
                    if let stringLiteral = element.expression.as(StringLiteralExprSyntax.self) {
                        templates.append(stringLiteral.segments.description)
                    }
                }
            }
        }
        return templates
    }

    /// Validates each URI template and emits diagnostics for any errors.
    /// Validation continues across all templates so developers see every
    /// problem at once.
    static func validateTemplates(
        templates: [String],
        node: AttributeSyntax,
        context: some MacroExpansionContext
    ) {
        for template in templates {
            let result = URITemplateValidator.validate(template)
            if let validationError = result.error {
                let diag = Diagnostic(node: Syntax(node), message: validationError)
                context.diagnose(diag)
            }
        }
    }

    /// Returns the union of all template variable names.
    static func collectPlaceholders(from templates: [String]) -> Set<String> {
        var allPlaceholders: Set<String> = []
        for template in templates {
            allPlaceholders.formUnion(URITemplateValidator.validate(template).variables)
        }
        return allPlaceholders
    }

    static func makeDescriptionArg(from metadata: ExtractedFunctionMetadata) -> String {
        if !metadata.documentation.description.isEmpty {
            return "\"\(metadata.documentation.description.escapedForSwiftString)\""
        }
        return "nil"
    }

    struct WrapperDetails {
        let parameterInfoStrings: [String]
        let functionParamNames: [String]
        let wrapperParamDetails: [WrapperParamDetail]
    }

    static func makeWrapperDetails(from metadata: ExtractedFunctionMetadata) -> WrapperDetails {
        var parameterInfoStrings: [String] = []
        var functionParamNames: [String] = []
        var wrapperParamDetails: [WrapperParamDetail] = []

        for parsedParam in metadata.parameters {
            functionParamNames.append(parsedParam.name)
            parameterInfoStrings.append(parsedParam.toMCPParameterInfo())
            wrapperParamDetails.append(WrapperParamDetail(
                name: parsedParam.name,
                label: parsedParam.label,
                type: parsedParam.typeString
            ))
        }

        return WrapperDetails(
            parameterInfoStrings: parameterInfoStrings,
            functionParamNames: functionParamNames,
            wrapperParamDetails: wrapperParamDetails
        )
    }

    static func diagnoseMissingParameters(
        placeholders: Set<String>,
        functionParamNames: [String],
        node: AttributeSyntax,
        context: some MacroExpansionContext
    ) {
        for placeholder in placeholders where !functionParamNames.contains(placeholder) {
            let diag = Diagnostic(
                node: Syntax(node),
                message: MCPResourceDiagnostic.missingParameterForPlaceholder(placeholder: placeholder)
            )
            context.diagnose(diag)
        }
    }

    static func diagnoseUnknownPlaceholders(
        functionParamNames: [String],
        placeholders: Set<String>,
        metadata: ExtractedFunctionMetadata,
        context: some MacroExpansionContext
    ) {
        for funcParamName in functionParamNames {
            guard let paramMeta = metadata.parameters.first(where: { $0.name == funcParamName }) else { continue }
            if !placeholders.contains(funcParamName) && paramMeta.defaultValueClause == nil {
                let originalParamSyntax = paramMeta.funcParam
                let diag = Diagnostic(
                    node: Syntax(originalParamSyntax),
                    message: MCPResourceDiagnostic.unknownPlaceholder(parameterName: funcParamName)
                )
                context.diagnose(diag)
            }
        }
    }
}
