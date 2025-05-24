import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `MCPResource` macro used to expose read-only resources.
///
/// This minimal implementation only validates that the provided URI template
/// matches the function's parameters.
public struct MCPResourceMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            let diag = Diagnostic(node: node, message: MCPResourceDiagnostic.onlyFunctions)
            context.diagnose(diag)
            return []
        }

        // Validate attribute argument is a string literal
        guard let argList = node.arguments?.as(LabeledExprListSyntax.self),
              let first = argList.first,
              first.label == nil,
              let stringLiteral = first.expression.as(StringLiteralExprSyntax.self)
        else {
            let diag = Diagnostic(node: node, message: MCPResourceDiagnostic.requiresStringLiteral)
            context.diagnose(diag)
            return []
        }

        let template = stringLiteral.segments.description
        let placeholderRegex = try NSRegularExpression(pattern: "\\{([^}]+)\\)")
        let ns = template as NSString
        let matches = placeholderRegex.matches(in: template, range: NSRange(location: 0, length: ns.length))
        var placeholders: [String] = []
        for m in matches {
            placeholders.append(ns.substring(with: m.range(at: 1)))
        }

        // Collect parameter names and check optional parameters
        var paramNames: [String] = []
        for param in funcDecl.signature.parameterClause.parameters {
            let name = param.secondName?.text ?? param.firstName.text
            paramNames.append(name)

            let typeText = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
            let isOptional = typeText.hasSuffix("?") || param.type.is(OptionalTypeSyntax.self) || param.type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            if isOptional && param.defaultValue == nil {
                let diag = Diagnostic(
                    node: Syntax(param.type),
                    message: MCPResourceDiagnostic.optionalParameterNeedsDefault(paramName: name)
                )
                context.diagnose(diag)
            }
        }

        // Check that each placeholder has a corresponding parameter
        for ph in placeholders {
            if !paramNames.contains(ph) {
                let diag = Diagnostic(node: node, message: MCPResourceDiagnostic.missingParameterForPlaceholder(placeholder: ph))
                context.diagnose(diag)
            }
        }

        // Check for parameters without matching placeholders
        for name in paramNames {
            if !placeholders.contains(name) {
                let param = funcDecl.signature.parameterClause.parameters.first { p in
                    let n = p.secondName?.text ?? p.firstName.text
                    return n == name
                }
                if let paramNode = param {
                    let diag = Diagnostic(
                        node: Syntax(paramNode),
                        message: MCPResourceDiagnostic.unknownPlaceholder(parameterName: name)
                    )
                    context.diagnose(diag)
                }
            }
        }

        return []
    }
}

