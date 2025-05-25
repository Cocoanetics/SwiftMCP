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
        
        // Extract placeholders from both path and query string
        let placeholderRegex = try NSRegularExpression(pattern: "\\{([^}]+)\\}")
        let ns = template as NSString
        let matches = placeholderRegex.matches(in: template, range: NSRange(location: 0, length: ns.length))
        var placeholders: [String] = []
        for m in matches {
            placeholders.append(ns.substring(with: m.range(at: 1)))
        }

        // Extract function name
        let functionName = funcDecl.name.text
        
        // Extract documentation
        let documentation = Documentation(from: funcDecl.leadingTrivia.description)
        
        // Extract description from documentation
        var descriptionArg = "nil"
        if !documentation.description.isEmpty {
            descriptionArg = "\"\(documentation.description.escapedForSwiftString)\""
        }
        
        // Extract public resource name and MIME type from arguments if provided
        var resourceName = functionName  // Default to function name
        var mimeTypeArg = "nil"

        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if argument.label?.text == "name",
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    resourceName = stringLiteral.segments.description // Override with provided name
                } else if argument.label?.text == "mimeType", 
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    let stringValue = stringLiteral.segments.description
                    mimeTypeArg = "\"\(stringValue)\""
                }
            }
        }

        // Collect parameter names and check optional parameters
        var paramNames: [String] = []
        var parameterInfos: [(name: String, label: String, type: String, defaultValue: String?)] = []
        var parameterString = ""
        
        for param in funcDecl.signature.parameterClause.parameters {
            let name = param.secondName?.text ?? param.firstName.text
            let label = param.firstName.text
            let typeText = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
            
            paramNames.append(name)

            let isOptional = typeText.hasSuffix("?") || 
                           param.type.is(OptionalTypeSyntax.self) || 
                           param.type.is(ImplicitlyUnwrappedOptionalTypeSyntax.self)
            
            if isOptional && param.defaultValue == nil {
                let diag = Diagnostic(
                    node: Syntax(param.type),
                    message: MCPResourceDiagnostic.optionalParameterNeedsDefault(paramName: name)
                )
                context.diagnose(diag)
            }
            
            // Extract parameter description
            var paramDescription = "nil"
            if let description = documentation.parameters[name], !description.isEmpty {
                paramDescription = "\"\(description.escapedForSwiftString)\""
            }
            
            // Extract default value if it exists
            var defaultValue: String? = nil
            var defaultValueString = "nil"
            if let defaultExpr = param.defaultValue?.value {
                let rawValue = defaultExpr.description.trimmingCharacters(in: .whitespaces)
                
                // Handle different types of default values
                if rawValue.hasPrefix(".") {
                    defaultValue = "\(typeText)\(rawValue)"
                    defaultValueString = "\"\(typeText)\(rawValue)\""
                } else if rawValue.contains(".") || 
                   rawValue == "true" || rawValue == "false" ||
                   Double(rawValue) != nil ||
                   rawValue == "nil" ||
                   (rawValue.hasPrefix("[") && rawValue.hasSuffix("]"))
                {
                    if rawValue == "[]" {
                        let arrayType = typeText.replacingOccurrences(of: "[", with: "Array<")
                            .replacingOccurrences(of: "]", with: ">")
                        defaultValue = "\(arrayType)()"
                    } else {
                        defaultValue = rawValue
                    }
                    defaultValueString = "\"\(rawValue)\""
                } else if let stringLiteral = defaultExpr.as(StringLiteralExprSyntax.self) {
                    let stringValue = stringLiteral.segments.description
                    defaultValue = "\"\(stringValue)\""
                    defaultValueString = "\"\\\"\(stringValue)\\\"\""
                } else {
                    defaultValue = "\"\(rawValue)\""
                    defaultValueString = "\"\\\"\(rawValue)\\\"\""
                }
            }
            
            if !parameterString.isEmpty {
                parameterString += ", "
            }
            
            let hasDefault = defaultValue != nil
            parameterString += "MCPResourceParameterInfo(name: \"\(name)\", type: \(typeText).self, description: \(paramDescription), isOptional: \(hasDefault), defaultValue: \(defaultValueString))"
            
            parameterInfos.append((name: name, label: label, type: typeText, defaultValue: defaultValue))
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
        
        // Extract return type information
        let returnTypeString: String
        if let returnType = funcDecl.signature.returnClause?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) {
            returnTypeString = returnType
        } else {
            returnTypeString = "Void"
        }

        // Create metadata registration
        let registrationDecl = """
        ///
        /// autogenerated resource metadata
        let __mcpResourceMetadata_\(functionName) = MCPResourceMetadata(
            uriTemplate: "\(template)",
            functionName: "\(functionName)",
            name: "\(resourceName)",
            description: \(descriptionArg),
            parameters: [\(parameterString)],
            returnType: \(returnTypeString).self,
            isAsync: \(funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil),
            isThrowing: \(funcDecl.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil),
            mimeType: \(mimeTypeArg)
        )
        """
        
        // Parameter list for calling the original function
        let parameterList = parameterInfos.map { param in
            if param.label == "_" {
                return param.name
            }
            return "\(param.label): \(param.name)"
        }.joined(separator: ", ")

        // Generate the wrapper method
        var wrapperMethod = """

        /// Autogenerated wrapper for \(functionName) that takes a dictionary of parameters and URI
        private func __mcpResourceCall_\(functionName)(_ params: [String: Sendable], requestedUri: URL, overrideMimeType: String?) async throws -> [MCPResourceContent] {
        """

        for info in parameterInfos {
            let paramName = info.name
            let originalParamType = info.type
            wrapperMethod += """
                let \(paramName): \(originalParamType) = try params.extractValue(named: "\(paramName)", as: \(originalParamType).self)
            """
        }

        // Resolve components for the function call
        let isThrowingText = funcDecl.signature.effectSpecifiers?.throwsClause?.throwsSpecifier != nil ? "try " : ""
        let isAsyncText = funcDecl.signature.effectSpecifiers?.asyncSpecifier != nil ? "await " : ""
        // functionName and parameterList are already strings.

        // This is the actual call to the original function, fully resolved.
        let concreteFunctionCall = "\(isThrowingText)\(isAsyncText)\(functionName)(\(parameterList))"

        // Use the user-provided concrete type name
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
        } else { // For other types (structs, Bool, [Double], Encodable arrays etc.)
            returnHandlingCode = """
                let result = \(concreteFunctionCall)
                return GenericResourceContent.fromResult(result, uri: requestedUri, mimeType: overrideMimeType)
            """
        }

        wrapperMethod += """
        \(returnHandlingCode)
        }
        """ // Close the __mcpResourceCall_ function

        return [
            DeclSyntax(stringLiteral: registrationDecl),
            DeclSyntax(stringLiteral: wrapperMethod)
        ]
    }
}

