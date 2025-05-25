//
//  FunctionMetadataExtractor.swift
//  SwiftMCPMacros
//
//  Created by Your Name/AI on $(date).
//

import SwiftSyntax
import SwiftSyntaxMacros
import SwiftDiagnostics

// Assuming Documentation struct is available and provides .escapedForSwiftString
// struct Documentation {
//     let description: String
//     let parameters: [String: String] // Param name to description
//     let returns: String?
//     init(from string: String) { /* ... */ }
// }
// extension String {
//    var escapedForSwiftString: String { /* ... */ }
// }

/// Holds detailed information about an extracted function parameter.
struct ParsedParameter {
    let funcParam: FunctionParameterSyntax // Original syntax for diagnostics/FixIts
    let name: String
    let label: String
    let typeSyntax: TypeSyntax
    let typeString: String
    let baseTypeString: String // Type string without optional marker (e.g., "String", "Int")
    let isOptional: Bool
    let defaultValueClause: InitializerClauseSyntax?
    let defaultValueForMetadata: String // String representation for metadata (e.g., "0", "\\"text\\"", "nil", "MyEnum.value")
    let description: String? // From documentation, already escaped for Swift string
}

/// Holds common metadata extracted from a function declaration.
struct ExtractedFunctionMetadata {
    let funcDecl: FunctionDeclSyntax
    let functionName: String
    let documentation: Documentation // The parsed documentation object
    let parameters: [ParsedParameter]
    let returnTypeSyntax: TypeSyntax?
    let returnTypeString: String // "Void" if no explicit return
    let returnDescription: String? // From documentation, already escaped for Swift string
    let isAsync: Bool
    let isThrowing: Bool
}

/// Utility to extract common metadata from a FunctionDeclSyntax.
struct FunctionMetadataExtractor {
    private let funcDecl: FunctionDeclSyntax
    private let context: any MacroExpansionContext

    init(funcDecl: FunctionDeclSyntax, context: any MacroExpansionContext) {
        self.funcDecl = funcDecl
        self.context = context
    }

    func extract() throws -> ExtractedFunctionMetadata {
        let functionName = funcDecl.name.text
        let documentation = Documentation(from: funcDecl.leadingTrivia.description)

        var parsedParameters: [ParsedParameter] = []

        for param in funcDecl.signature.parameterClause.parameters {
            let paramName = param.secondName?.text ?? param.firstName.text
            let paramLabel = param.firstName.text
            let paramTypeSyntax = param.type
            let paramTypeString = paramTypeSyntax.description.trimmingCharacters(in: .whitespacesAndNewlines)

            let isOptionalType = paramTypeSyntax.is(OptionalTypeSyntax.self) ||
                               paramTypeSyntax.is(ImplicitlyUnwrappedOptionalTypeSyntax.self) ||
                               paramTypeString.hasSuffix("?") ||
                               paramTypeString.hasSuffix("!")
            
            let baseTypeString: String
            if isOptionalType {
                if paramTypeString.hasSuffix("?") {
                    baseTypeString = String(paramTypeString.dropLast())
                } else if paramTypeString.hasSuffix("!") {
                    baseTypeString = String(paramTypeString.dropLast())
                } else if let optType = paramTypeSyntax.as(OptionalTypeSyntax.self) {
                    baseTypeString = optType.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if let iuoType = paramTypeSyntax.as(ImplicitlyUnwrappedOptionalTypeSyntax.self) {
                    baseTypeString = iuoType.wrappedType.description.trimmingCharacters(in: .whitespacesAndNewlines)
                }
                else {
                    baseTypeString = paramTypeString // Should not happen if isOptional is true
                }
            } else {
                baseTypeString = paramTypeString
            }


            var paramDocDescription: String? = nil
            if let doc = documentation.parameters[paramName], !doc.isEmpty {
                paramDocDescription = "\"\(doc.escapedForSwiftString)\""
            }

            let defaultValueClause = param.defaultValue
            let defaultValueForMetadata = try processDefaultValue(
                defaultValueClause?.value,
                paramTypeString: baseTypeString, // Pass base type for enum cases like .value
                isArray: paramTypeSyntax.is(ArrayTypeSyntax.self) || paramTypeString.hasPrefix("[") 
            )

            // Common diagnostic for optional parameters needing default values
            if isOptionalType && defaultValueClause == nil {
                let diagnostic = Diagnostic(
                    node: Syntax(paramTypeSyntax),
                    // Using a generic diagnostic message here, specific macros might want to customize
                    message: MCPToolDiagnostic.optionalParameterNeedsDefault(paramName: paramName, typeName: paramTypeString), 
                    fixIts: [
                        FixIt(message: MCPToolFixItMessage.addDefaultValue(paramName: paramName),
                              changes: [
                                  .replace(oldNode: Syntax(param),
                                           newNode: Syntax(param.with(\.defaultValue, InitializerClauseSyntax(
                                               equal: .equalToken(leadingTrivia: .space, trailingTrivia: .space),
                                               value: ExprSyntax(NilLiteralExprSyntax())
                                           ))))
                              ])
                    ]
                )
                context.diagnose(diagnostic)
            }
            
            parsedParameters.append(ParsedParameter(
                funcParam: param,
                name: paramName,
                label: paramLabel,
                typeSyntax: paramTypeSyntax,
                typeString: paramTypeString,
                baseTypeString: baseTypeString,
                isOptional: isOptionalType,
                defaultValueClause: defaultValueClause,
                defaultValueForMetadata: defaultValueForMetadata,
                description: paramDocDescription
            ))
        }

        let returnTypeSyntax = funcDecl.signature.returnClause?.type
        let returnTypeString = returnTypeSyntax?.description.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Void"
        var returnDocDescription: String? = nil
        if let doc = documentation.returns, !doc.isEmpty {
            returnDocDescription = "\"\(doc.escapedForSwiftString)\""
        }

        let isAsync = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil
        let isThrowing = funcDecl.signature.effectSpecifiers?.throwsClause != nil

        return ExtractedFunctionMetadata(
            funcDecl: funcDecl,
            functionName: functionName,
            documentation: documentation,
            parameters: parsedParameters,
            returnTypeSyntax: returnTypeSyntax,
            returnTypeString: returnTypeString,
            returnDescription: returnDocDescription,
            isAsync: isAsync,
            isThrowing: isThrowing
        )
    }

    private func processDefaultValue(_ defaultExpr: ExprSyntax?, paramTypeString: String, isArray: Bool) throws -> String {
        guard let expr = defaultExpr else { return "nil" }

        let rawValue = expr.description.trimmingCharacters(in: .whitespaces)

        if expr.is(NilLiteralExprSyntax.self) {
            return "nil"
        } else if let stringLiteral = expr.as(StringLiteralExprSyntax.self) {
            return "\"\(stringLiteral.segments.description.escapedForSwiftString)\""
        } else if expr.is(BooleanLiteralExprSyntax.self) ||
                  expr.is(IntegerLiteralExprSyntax.self) ||
                  expr.is(FloatLiteralExprSyntax.self) {
            return rawValue
        } else if rawValue.hasPrefix(".") { // Enum case like .someCase
            return "\(paramTypeString)\(rawValue)"
        } else if expr.is(ArrayExprSyntax.self) && rawValue == "[]" {
             // For empty array literals, use the parameter type to construct Array<Type>()
            if isArray {
                 // paramTypeString here is the base type like "MyType" if original was "[MyType]?"
                 // or "String" if original was "[String]".
                 // This logic might need refinement if paramTypeString is already "Array<Foo>"
                if paramTypeString.hasPrefix("Array<") || paramTypeString.hasPrefix("Dictionary<") {
                    return "\(paramTypeString)()"
                } else {
                    // Assuming it's like "String" for "[String]"
                    return "Array<\(paramTypeString)>()"
                }
            } else {
                 // Fallback for non-array types with "[]" - should be caught by compiler
                return "[]"
            }
        }
        // For other complex expressions (e.g., fully qualified enum, function calls, other literals)
        // we return their verbatim string representation.
        // This includes cases like `MyEnum.value`, `[1, 2]`, `["a": 1]`.
        return rawValue
    }
} 