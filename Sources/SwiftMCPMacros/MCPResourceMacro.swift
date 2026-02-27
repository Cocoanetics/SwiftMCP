import Foundation
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

/// Implementation of the `MCPResource` macro used to expose read-only resources.
///
/// This macro transforms a function into an MCP resource by generating metadata and wrapper
/// functions for parameter handling and type safety.
///
/// Example usage:
/// ```swift
/// @MCPResource("users://{user_id}/profile?locale={lang}")
/// func getUserProfile(user_id: Int, lang: String = "en") -> ProfileResource
/// ```
public struct MCPResourceMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            let diag = Diagnostic(node: Syntax(node), message: MCPResourceDiagnostic.onlyFunctions)
            context.diagnose(diag)
            return []
        }

        let extractor = FunctionMetadataExtractor(funcDecl: funcDecl, context: context)
        let commonMetadata = try extractor.extract()

        let functionName = commonMetadata.functionName

        // Extract templates from the macro arguments
        var templates: [String] = []

        guard let argList = node.arguments?.as(LabeledExprListSyntax.self) else {
            let diag = Diagnostic(node: Syntax(node), message: MCPResourceDiagnostic.requiresStringLiteral)
            context.diagnose(diag)
            return []
        }

        // Process all unlabeled arguments as templates
        for arg in argList {
            if arg.label == nil {
                if let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self) {
                    let template = stringLiteral.segments.description
                    templates.append(template)
                } else if let arrayExpr = arg.expression.as(ArrayExprSyntax.self) {
                    // Handle array of templates
                    for element in arrayExpr.elements {
                        if let stringLiteral = element.expression.as(StringLiteralExprSyntax.self) {
                            let template = stringLiteral.segments.description
                            templates.append(template)
                        }
                    }
                }
            }
        }

        if templates.isEmpty {
            let diag = Diagnostic(node: Syntax(node), message: MCPResourceDiagnostic.requiresStringLiteral)
            context.diagnose(diag)
            return []
        }

        // Validate all templates and collect all variables
        var allPlaceholders: Set<String> = []
        for template in templates {
            let validationResult = URITemplateValidator.validate(template)
            if let validationError = validationResult.error {
                let diag = Diagnostic(
                    node: Syntax(node),
                    message: validationError
                )
                context.diagnose(diag)
            // Continue processing even with validation errors for better developer experience
            }

            // Extract variables using the validator (which properly handles RFC 6570 syntax)
            let placeholders = validationResult.variables
            allPlaceholders.formUnion(placeholders)
        }

        var descriptionArg = "nil"
        if !commonMetadata.documentation.description.isEmpty {
            descriptionArg = "\"\(commonMetadata.documentation.description.escapedForSwiftString)\""
        }

        var resourceName = functionName
        var mimeTypeArg = "nil"

        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if argument.label == nil { continue }

                if argument.label?.text == "name",
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    resourceName = stringLiteral.segments.description
                } else if argument.label?.text == "mimeType", 
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    let stringValue = stringLiteral.segments.description
                    mimeTypeArg = "\"\(stringValue.escapedForSwiftString)\""
                }
            }
        }

        // Generate parameter info strings using the new unified approach
        var parameterInfoStrings: [String] = []
        var functionParamNames: [String] = []
        var wrapperParamDetails: [(name: String, label: String, type: String)] = []

        for parsedParam in commonMetadata.parameters {
            functionParamNames.append(parsedParam.name)
            parameterInfoStrings.append(parsedParam.toMCPParameterInfo())
            wrapperParamDetails.append((name: parsedParam.name, label: parsedParam.label, type: parsedParam.typeString))
        }

        for ph in allPlaceholders {
            if !functionParamNames.contains(ph) {
                let diag = Diagnostic(node: Syntax(node), message: MCPResourceDiagnostic.missingParameterForPlaceholder(placeholder: ph))
                context.diagnose(diag)
            }
        }

        for funcParamName in functionParamNames {
            // Find the parameter metadata
            guard let paramMeta = commonMetadata.parameters.first(where: { $0.name == funcParamName }) else { continue }
            // Only require a placeholder if the parameter does NOT have a default value
            if !allPlaceholders.contains(funcParamName) && paramMeta.defaultValueClause == nil {
                let originalParamSyntax = paramMeta.funcParam
                let diag = Diagnostic(
                    node: Syntax(originalParamSyntax),
                    message: MCPResourceDiagnostic.unknownPlaceholder(parameterName: funcParamName)
                )
                context.diagnose(diag)
            }
        }

        let returnTypeString = commonMetadata.returnTypeString

        let returnDescriptionString = commonMetadata.returnDescription ?? "nil"

        // Generate the Set of templates for the metadata
        let templatesSetString = "[\(templates.map { "\"\($0)\"" }.joined(separator: ", "))]"

        // Generate the metadata variable
        let metadataDeclaration = """
/// Metadata for the \(functionName) resource
nonisolated var __mcpResourceMetadata_\(functionName): MCPResourceMetadata {
   MCPResourceMetadata(
   uriTemplates: Set(\(templatesSetString)),
   name: "\(resourceName)",
   functionName: "\(functionName)",
   description: \(descriptionArg),
   parameters: [\(parameterInfoStrings.joined(separator: ", "))],
   returnType: \(returnTypeString).self,
   returnTypeDescription: \(returnDescriptionString),
   isAsync: \(commonMetadata.isAsync),
   isThrowing: \(commonMetadata.isThrowing),
   mimeType: \(mimeTypeArg)
   )
}
"""

        let callParameterList = wrapperParamDetails.map { param in
            if param.label == "_" {
                return param.name
            }
            return "\(param.label): \(param.name)"
        }.joined(separator: ", ")

        var wrapperMethod = """

        /// Autogenerated wrapper for \(functionName) that takes a dictionary of parameters and URI
"""
        if !commonMetadata.propagatedAttributes.isEmpty {
            for attribute in commonMetadata.propagatedAttributes {
                wrapperMethod += "\n        \(attribute)"
            }
        }
        wrapperMethod += "\n        func __mcpResourceCall_\(functionName)(_ params: [String: Sendable], requestedUri: URL, overrideMimeType: String?) async throws -> [MCPResourceContent] {\n"

        for detail in wrapperParamDetails {
            wrapperMethod += """
                let \(detail.name): \(detail.type) = try params.extractValue(named: "\(detail.name)", as: \(detail.type).self)
            """
        }

        let concreteFunctionCall = "\(commonMetadata.isThrowing ? "try " : "")\(commonMetadata.isAsync ? "await " : "")\(functionName)(\(callParameterList))"
        let concreteResourceContentTypeName = "GenericResourceContent"

        var returnHandlingCode: String
        if returnTypeString == "String" {
            returnHandlingCode = """
                let result = \(concreteFunctionCall)
                return [\(concreteResourceContentTypeName)(uri: requestedUri, mimeType: overrideMimeType ?? "text/plain", text: result)]
            """
        } else if returnTypeString == "Data" {
            returnHandlingCode = """
                let result = \(concreteFunctionCall)
                return [\(concreteResourceContentTypeName)(uri: requestedUri, mimeType: overrideMimeType ?? "application/octet-stream", blob: result)]
            """
        } else if returnTypeString == "MCPResourceContent" {
            returnHandlingCode = """
                let result = \(concreteFunctionCall)
                return [result]
            """
        } else if returnTypeString == "[MCPResourceContent]" || returnTypeString == "[\(concreteResourceContentTypeName)]" {
            returnHandlingCode = """
                let result = \(concreteFunctionCall)
                return result
            """
        } else {
            returnHandlingCode = """
                let result = \(concreteFunctionCall)
                return GenericResourceContent.fromResult(result, uri: requestedUri, mimeType: overrideMimeType)
            """
        }

        wrapperMethod += """
        \(returnHandlingCode)
        }
        """

        return [
            DeclSyntax(stringLiteral: metadataDeclaration),
            DeclSyntax(stringLiteral: wrapperMethod)
        ]
    }
}
