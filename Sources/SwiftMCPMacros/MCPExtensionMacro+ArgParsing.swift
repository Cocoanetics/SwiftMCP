//
//  MCPExtensionMacro+ArgParsing.swift
//  SwiftMCPMacros
//
//  Parsers for `@MCPTool` / `@MCPResource` / `@MCPPrompt` attribute
//  arguments as they appear inside an `@MCPExtension` body. Decomposed
//  into per-label appliers to keep cyclomatic complexity bounded.
//

import Foundation
import SwiftSyntax

extension MCPExtensionMacro {
    struct ToolArgs {
        var wireName: String
        var descriptionArg: String
        var isConsequential: String
        var annotationsArg: String
    }

    /// Intermediate accumulator populated while iterating over labeled
    /// arguments before being materialised into `ToolArgs`.
    private struct ParsedToolArgs {
        var wireName: String
        var descriptionArg: String = "nil"
        var isConsequentialArg: String = "true"
        var hintsFromOptionSet: [String] = []
        var readOnlyHintArg: String?
        var destructiveHintArg: String?
        var idempotentHintArg: String?
        var openWorldHintArg: String?
    }

    static func parseToolArgs(attribute: AttributeSyntax, defaults: ExtractedFunctionMetadata) -> ToolArgs {
        var parsed = ParsedToolArgs(wireName: defaults.functionName)

        if let argList = attribute.arguments?.as(LabeledExprListSyntax.self) {
            for arg in argList {
                applyToolArg(arg, to: &parsed)
            }
        }

        if parsed.descriptionArg == "nil", !defaults.documentation.description.isEmpty {
            parsed.descriptionArg = "\"\(defaults.documentation.description.escapedForSwiftString)\""
        }

        return ToolArgs(
            wireName: parsed.wireName,
            descriptionArg: parsed.descriptionArg,
            isConsequential: parsed.isConsequentialArg,
            annotationsArg: makeAnnotationsArg(from: parsed)
        )
    }

    private static func applyToolArg(
        _ arg: LabeledExprListSyntax.Element,
        to parsed: inout ParsedToolArgs
    ) {
        guard let label = arg.label?.text else { return }
        switch label {
        case "name":
            if let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                parsed.wireName = lit.segments.description
            }
        case "description":
            if let lit = arg.expression.as(StringLiteralExprSyntax.self) {
                parsed.descriptionArg = "\"\(lit.segments.description.escapedForSwiftString)\""
            }
        case "hints":
            applyToolHintsArg(arg.expression, to: &parsed.hintsFromOptionSet)
        case "isConsequential":
            if let lit = arg.expression.as(BooleanLiteralExprSyntax.self) {
                parsed.isConsequentialArg = lit.literal.text
            }
        default:
            applyLegacyHint(label: label, expression: arg.expression, to: &parsed)
        }
    }

    /// Applies the legacy `*Hint:` boolean arguments. Splitting these out
    /// keeps the per-switch complexity bounded.
    private static func applyLegacyHint(
        label: String,
        expression: ExprSyntax,
        to parsed: inout ParsedToolArgs
    ) {
        guard let lit = expression.as(BooleanLiteralExprSyntax.self) else { return }
        switch label {
        case "readOnlyHint":
            parsed.readOnlyHintArg = lit.literal.text
        case "destructiveHint":
            parsed.destructiveHintArg = lit.literal.text
        case "idempotentHint":
            parsed.idempotentHintArg = lit.literal.text
        case "openWorldHint":
            parsed.openWorldHintArg = lit.literal.text
        default:
            return
        }
    }

    private static func applyToolHintsArg(_ expression: ExprSyntax, to hints: inout [String]) {
        guard let arr = expression.as(ArrayExprSyntax.self) else { return }
        for element in arr.elements {
            if let memberAccess = element.expression.as(MemberAccessExprSyntax.self) {
                hints.append(".\(memberAccess.declName.baseName.text)")
            }
        }
    }

    private static func makeAnnotationsArg(from parsed: ParsedToolArgs) -> String {
        var allHints = Set(parsed.hintsFromOptionSet)
        if parsed.readOnlyHintArg == "true" { allHints.insert(".readOnly") }
        if parsed.destructiveHintArg == "true" { allHints.insert(".destructive") }
        if parsed.idempotentHintArg == "true" { allHints.insert(".idempotent") }
        if parsed.openWorldHintArg == "true" { allHints.insert(".openWorld") }

        if allHints.isEmpty {
            return "nil"
        }
        return "MCPToolAnnotations(hints: [\(allHints.sorted().joined(separator: ", "))])"
    }

    struct ResourceArgs {
        var templates: [String]
        var resourceName: String
        var descriptionArg: String
        var mimeTypeArg: String
    }

    static func parseResourceArgs(
        attribute: AttributeSyntax,
        defaults: ExtractedFunctionMetadata
    ) -> ResourceArgs {
        var templates: [String] = []
        var resourceName = defaults.functionName
        var descriptionArg = "nil"
        var mimeTypeArg = "nil"

        if let argList = attribute.arguments?.as(LabeledExprListSyntax.self) {
            for arg in argList {
                if arg.label == nil {
                    appendResourceTemplates(arg.expression, to: &templates)
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

    private static func appendResourceTemplates(_ expression: ExprSyntax, to templates: inout [String]) {
        if let lit = expression.as(StringLiteralExprSyntax.self) {
            templates.append(lit.segments.description)
        } else if let arr = expression.as(ArrayExprSyntax.self) {
            for element in arr.elements {
                if let lit = element.expression.as(StringLiteralExprSyntax.self) {
                    templates.append(lit.segments.description)
                }
            }
        }
    }

    static func parsePromptDescription(
        attribute: AttributeSyntax,
        defaults: ExtractedFunctionMetadata
    ) -> String {
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
