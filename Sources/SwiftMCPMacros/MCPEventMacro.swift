import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

/// `@MCPEvent` declares an event type listed by `events/list`. The annotated
/// function's parameters are the subscriber filter, its return type the payload.
public struct MCPEventMacro: PeerMacro {
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

        // Inside an extension: `@MCPExtension` regenerates the metadata at the
        // extension level (stored `let`s are illegal there).
        if let enclosing = MCPMacroContextDetection.enclosingExtension(in: context) {
            if !MCPMacroContextDetection.hasMCPExtensionAttribute(enclosing) {
                let diag = Diagnostic(
                    node: Syntax(funcDecl.name),
                    message: MCPToolDiagnostic.missingMCPExtensionAttribute(macroName: "MCPEvent")
                )
                context.diagnose(diag)
            }
            return []
        }

        let extracted = try FunctionMetadataExtractor(funcDecl: funcDecl, context: context).extract()
        let literal = metadataLiteral(attribute: node, extracted: extracted)
        let eventName = eventName(attribute: node, functionName: extracted.functionName)

        return [DeclSyntax(stringLiteral: """
/// Metadata for the \(eventName) event
nonisolated private let __mcpEventMetadata_\(extracted.functionName) = \(literal)
""")]
    }

    /// The `MCPEventMetadata(...)` initializer expression for `extracted`.
    static func metadataLiteral(attribute: AttributeSyntax, extracted: ExtractedFunctionMetadata) -> String {
        let descriptionArg = MCPExtensionMacro.parsePromptDescription(attribute: attribute, defaults: extracted)
        let returnDescription = extracted.returnDescription ?? "nil"
        let name = eventName(attribute: attribute, functionName: extracted.functionName)
        return """
MCPEventMetadata(
   name: "\(name)",
   description: \(descriptionArg),
   parameters: [\(extracted.parameters.map { $0.toMCPParameterInfo() }.joined(separator: ", "))],
   returnType: \(extracted.returnTypeString).self,
   returnTypeDescription: \(returnDescription),
   isAsync: \(extracted.isAsync),
   isThrowing: \(extracted.isThrowing),
   delivery: \(deliveryArgument(attribute: attribute))
)
"""
    }

    /// Wire event name: `@MCPEvent(name:)` when set, otherwise the function name.
    static func eventName(attribute: AttributeSyntax, functionName: String) -> String {
        guard let args = attribute.arguments?.as(LabeledExprListSyntax.self),
              let arg = args.first(where: { $0.label?.text == "name" }),
              let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self) else {
            return functionName
        }
        return stringLiteral.segments.description
    }

    /// The `delivery:` argument expression source (literal or not), or `nil`.
    private static func deliveryArgument(attribute: AttributeSyntax) -> String {
        guard let args = attribute.arguments?.as(LabeledExprListSyntax.self),
              let arg = args.first(where: { $0.label?.text == "delivery" }),
              !arg.expression.is(NilLiteralExprSyntax.self) else { return "nil" }
        return arg.expression.trimmedDescription
    }
}
