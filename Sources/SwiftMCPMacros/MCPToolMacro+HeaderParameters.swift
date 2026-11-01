import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros

extension MCPToolMacro {
    /// Error-diagnoses a `headerParameters` argument the macro cannot read at
    /// expansion time — anything but an array of plain string literals. Without
    /// this, such elements are silently dropped and the tool loses its
    /// `x-mcp-header` annotation with no hint why.
    static func diagnoseNonLiteralHeaderParameters(
        _ expression: ExprSyntax?,
        context: some MacroExpansionContext
    ) {
        guard let expression else { return }
        let elements: [ExprSyntax]
        if let arrayExpr = expression.as(ArrayExprSyntax.self) {
            elements = arrayExpr.elements.map { $0.expression }
        } else {
            elements = [expression]
        }
        for element in elements {
            let isPlainLiteral = element.as(StringLiteralExprSyntax.self)?.segments
                .allSatisfy { $0.is(StringSegmentSyntax.self) } ?? false
            if !isPlainLiteral {
                context.diagnose(Diagnostic(
                    node: Syntax(element),
                    message: MCPToolDiagnostic.nonLiteralHeaderParameter
                ))
            }
        }
    }

    /// The validated `headerParameters` set: names that match no function
    /// parameter get an error diagnostic (a typo would otherwise silently
    /// annotate nothing).
    static func validatedHeaderParameters(
        _ headerParameters: [String],
        commonMetadata: ExtractedFunctionMetadata,
        funcDecl: FunctionDeclSyntax,
        context: some MacroExpansionContext
    ) -> Set<String> {
        let parameterNames = Set(commonMetadata.parameters.map { $0.name })
        for headerParam in headerParameters where !parameterNames.contains(headerParam) {
            let diagnostic = Diagnostic(
                node: Syntax(funcDecl.name),
                message: MCPToolDiagnostic.unknownHeaderParameter(
                    paramName: headerParam, functionName: commonMetadata.functionName
                )
            )
            context.diagnose(diagnostic)
        }
        return Set(headerParameters)
    }
}
