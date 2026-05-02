//
//  MCPToolHintsParser.swift
//  SwiftMCPMacros
//
//  Shared parsing helpers for the `hints:` argument used by both
//  `@MCPTool` and `@MCPAppIntentTool`.
//

import SwiftSyntax

/// Extracts hint member names (e.g. `.readOnly`) from a `hints:` argument expression.
///
/// Supports both array-literal form (`[.readOnly, .destructive]`) and a single
/// OptionSet member access (`.readOnly`) — the latter is valid Swift for any
/// `ExpressibleByArrayLiteral` / OptionSet but the array variant must still be
/// accepted because that's how the API is documented.
func parseHintsExpression(_ expression: ExprSyntax) -> [String] {
    if let arrayExpr = expression.as(ArrayExprSyntax.self) {
        return arrayExpr.elements.compactMap { element in
            element.expression.as(MemberAccessExprSyntax.self).map {
                ".\($0.declName.baseName.text)"
            }
        }
    }
    if let memberAccess = expression.as(MemberAccessExprSyntax.self) {
        return [".\(memberAccess.declName.baseName.text)"]
    }
    return []
}
