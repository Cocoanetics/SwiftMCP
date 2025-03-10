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
 
 This macro extracts metadata from a function declaration and generates
 a peer declaration that registers the function with the MCP system.
 */
public struct MCPToolMacro: PeerMacro {
    /**
     Expands the macro to provide peers for the declaration.
     
     - Parameters:
       - node: The attribute syntax node
       - declaration: The declaration syntax
       - context: The macro expansion context
     
     - Returns: An array of declaration syntax nodes
     */
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Handle function declarations
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            let diagnostic = Diagnostic(node: node, message: MCPToolDiagnostic.onlyFunctions)
            context.diagnose(diagnostic)
            return []
        }
        
        // Extract function name
        let functionName = funcDecl.name.text
        
        // Extract description from the attribute if provided
        var descriptionArg = "nil"
        var hasExplicitDescription = false
        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if argument.label?.text == "description", let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    // Extract the string value from the string literal
                    let stringValue = stringLiteral.segments.description
                    // Remove quotes and escape special characters for string interpolation
                    let cleanedValue = stringValue
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    descriptionArg = "\"\(cleanedValue)\""
                    hasExplicitDescription = true
                    break
                }
            }
        }
        
        // If no description was provided in the attribute, try to extract it from the leading documentation comment
        var foundDescriptionInDocs = false
        if descriptionArg == "nil" {
            let leadingTrivia = funcDecl.leadingTrivia.description
            
            // Extract the function description from Swift's standard documentation styles
            var foundDescription = false
            
            // 1. Check for /// style comments (Swift's preferred style)
            let docLines = leadingTrivia.split(separator: "\n")
            
            // First try to find /// style comments
            for line in docLines {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.starts(with: "///") {
                    let docContent = trimmed.dropFirst(3).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !docContent.isEmpty && !foundDescription {
                        descriptionArg = "\"\(docContent.replacingOccurrences(of: "\"", with: "\\\""))\""
                        foundDescription = true
                        foundDescriptionInDocs = true
                        break
                    }
                }
            }
            
            // If no /// comments, try /** */ style
            if !foundDescription {
                let docBlockPattern = try? NSRegularExpression(pattern: "/\\*\\*(.*?)\\*/", options: [.dotMatchesLineSeparators])
                if let docBlockPattern = docBlockPattern,
                   let match = docBlockPattern.firstMatch(in: leadingTrivia, options: [], range: NSRange(leadingTrivia.startIndex..., in: leadingTrivia)) {
                    if let range = Range(match.range(at: 1), in: leadingTrivia) {
                        let docContent = leadingTrivia[range].trimmingCharacters(in: .whitespacesAndNewlines)
                        if !docContent.isEmpty {
                            // Clean up the doc content by removing * at the beginning of lines
                            let cleanedContent = docContent.split(separator: "\n")
                                .map { line -> String in
                                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if trimmed.starts(with: "*") {
                                        return trimmed.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
                                    }
                                    return trimmed
                                }
                                .first ?? ""
                            
                            if !cleanedContent.isEmpty {
                                // Ensure the description is properly escaped and terminated
                                let escapedContent = cleanedContent.replacingOccurrences(of: "\"", with: "\\\"")
                                                                  .replacingOccurrences(of: "\n", with: " ")
                                descriptionArg = "\"\(escapedContent)\""
                                foundDescription = true
                                foundDescriptionInDocs = true
                            }
                        }
                    }
                }
            }
        }
        
        // If no description was found, emit a warning
        if descriptionArg == "nil" && !hasExplicitDescription && !foundDescriptionInDocs {
            let diagnostic = Diagnostic(node: funcDecl.name, message: MCPToolDiagnostic.missingDescription(functionName: functionName))
            context.diagnose(diagnostic)
        }
        
        // Extract parameter information
        var parameterString = ""
        var parameterInfos: [(name: String, type: String, defaultValue: String?)] = []
        
        for param in funcDecl.signature.parameterClause.parameters {
            let paramName = param.firstName.text
            let paramType = param.type.description.trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Store parameter info for wrapper function generation
            var defaultValueStr: String? = nil
            
            // Extract parameter description from documentation comments
            var paramDescription = "nil"
            let leadingTrivia = funcDecl.leadingTrivia.description
            
            // Look for parameter descriptions in the format: "- Parameter paramName: description"
            let paramPattern = try? NSRegularExpression(pattern: "- [Pp]arameter\\s+\(paramName):\\s*(.*?)(?=\\n\\s*-|\\n\\s*\\n|$)", options: [.dotMatchesLineSeparators])
            if let paramPattern = paramPattern,
               let match = paramPattern.firstMatch(in: leadingTrivia, options: [], range: NSRange(leadingTrivia.startIndex..., in: leadingTrivia)) {
                if let range = Range(match.range(at: 1), in: leadingTrivia) {
                    let description = leadingTrivia[range].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !description.isEmpty {
                        // Ensure the parameter description is properly escaped and terminated
                        // Also ensure it doesn't include other parameter descriptions
                        let lines = description.split(separator: "\n")
                        let firstLine = String(lines.first ?? "")
                        let escapedDescription = firstLine.replacingOccurrences(of: "\"", with: "\\\"")
                        paramDescription = "\"\(escapedDescription)\""
                    }
                }
            }
            
            // Extract default value if it exists
            var defaultValue = "nil"
            if let defaultExpr = param.defaultValue?.value {
                // Check for supported default value types
                var isValidDefaultType = false
                var typeName = "unknown"
                
                // For simple literals, we can use their string representation
                if let intLiteral = defaultExpr.as(IntegerLiteralExprSyntax.self) {
                    defaultValue = "\"\(intLiteral.description)\""
                    defaultValueStr = intLiteral.description
                    isValidDefaultType = true
                } else if let floatLiteral = defaultExpr.as(FloatLiteralExprSyntax.self) {
                    defaultValue = "\"\(floatLiteral.description)\""
                    defaultValueStr = floatLiteral.description
                    isValidDefaultType = true
                } else if let boolLiteral = defaultExpr.as(BooleanLiteralExprSyntax.self) {
                    defaultValue = "\"\(boolLiteral.description)\""
                    defaultValueStr = boolLiteral.description
                    isValidDefaultType = true
                } else if let stringLiteral = defaultExpr.as(StringLiteralExprSyntax.self) {
                    // For string literals, we need to wrap them in quotes
                    let stringValue = stringLiteral.segments.description
                        .replacingOccurrences(of: "\"", with: "\\\"")
                    defaultValue = "\"\(stringValue)\""
                    defaultValueStr = "\"\(stringValue)\""
                    isValidDefaultType = true
                } else if defaultExpr.is(NilLiteralExprSyntax.self) {
                    // For nil literals, we can use nil
                    defaultValue = "nil"
                    defaultValueStr = "nil"
                    isValidDefaultType = true
                } else if let arrayExpr = defaultExpr.as(ArrayExprSyntax.self) {
                    // For array literals, convert to a string representation
                    defaultValue = "\"\(arrayExpr.description)\""
                    defaultValueStr = arrayExpr.description
                    isValidDefaultType = true
                } else {
                    // For unsupported types, emit a diagnostic
                    typeName = defaultExpr.description
                    let diagnostic = Diagnostic(
                        node: defaultExpr,
                        message: MCPToolDiagnostic.invalidDefaultValueType(
                            paramName: paramName,
                            typeName: typeName
                        )
                    )
                    context.diagnose(diagnostic)
                }
                
                // If it's not a valid type, don't include the default value
                if !isValidDefaultType {
                    defaultValue = "nil"
                    defaultValueStr = nil
                }
            }
            
            if !parameterString.isEmpty {
                parameterString += ", "
            }
            
            parameterString += "MCPToolParameterInfo(name: \"\(paramName)\", type: \"\(paramType)\", description: \(paramDescription), defaultValue: \(defaultValue))"
            
            // Store parameter info for wrapper function generation
            parameterInfos.append((name: paramName, type: paramType, defaultValue: defaultValueStr))
        }
        
        // Extract return type if it exists
        let returnTypeString: String
        let returnTypeForBlock: String
        if let returnType = funcDecl.signature.returnClause?.type.description.trimmingCharacters(in: .whitespacesAndNewlines) {
            returnTypeString = "\"\(returnType)\""
            returnTypeForBlock = returnType
        } else {
            returnTypeString = "nil"
            returnTypeForBlock = "Void"
        }
        
        // Create a registration statement using string interpolation for simplicity
        let registrationDecl = """
        ///
        /// autogenerated
        let __metadata_\(functionName) = MCPToolMetadata(name: "\(functionName)", parameters: [\(parameterString)], returnType: \(returnTypeString),  description: \(descriptionArg))
        """
        
        // Generate the wrapper method
        var wrapperMethod = """
        
        /// Autogenerated wrapper for \(functionName) that takes a dictionary of parameters
        func __call_\(functionName)(_ params: [String: Any]) throws -> Any {
        """
        
        // Add parameter extraction code
        for param in parameterInfos {
            let paramName = param.name
            let paramType = param.type
            
            // If it has a default value, use conditional binding
            if let defaultValue = param.defaultValue {
                if param.type == "Double" || param.type == "Float" {
                    wrapperMethod += """
                    
                    let \(paramName): \(paramType)
                    if let paramValue = params["\(paramName)"] as? \(paramType) {
                        \(paramName) = paramValue
                    } else if let intValue = params["\(paramName)"] as? Int {
                        \(paramName) = \(paramType)(intValue)
                    } else if let stringValue = params["\(paramName)"] as? String, let parsedValue = \(paramType)(stringValue) {
                        \(paramName) = parsedValue
                    } else {
                        // Use default value from function definition
                        \(paramName) = \(defaultValue)
                    }
                    """
                } else if param.type == "Int" {
                    wrapperMethod += """
                    
                    let \(paramName): \(paramType)
                    if let paramValue = params["\(paramName)"] as? \(paramType) {
                        \(paramName) = paramValue
                    } else if let doubleValue = params["\(paramName)"] as? Double {
                        \(paramName) = \(paramType)(doubleValue)
                    } else if let stringValue = params["\(paramName)"] as? String, let parsedValue = \(paramType)(stringValue) {
                        \(paramName) = parsedValue
                    } else {
                        // Use default value from function definition
                        \(paramName) = \(defaultValue)
                    }
                    """
                } else {
                    wrapperMethod += """
                    
                    let \(paramName): \(paramType)
                    if let paramValue = params["\(paramName)"] as? \(paramType) {
                        \(paramName) = paramValue
                    } else {
                        // Use default value from function definition
                        \(paramName) = \(defaultValue)
                    }
                    """
                }
            } else {
                // For required parameters, use guard with type conversion
                if param.type == "Double" || param.type == "Float" {
                    wrapperMethod += """
                    
                    let \(paramName): \(paramType)
                    if let paramValue = params["\(paramName)"] as? \(paramType) {
                        \(paramName) = paramValue
                    } else if let intValue = params["\(paramName)"] as? Int {
                        \(paramName) = \(paramType)(intValue)
                    } else if let stringValue = params["\(paramName)"] as? String, let parsedValue = \(paramType)(stringValue) {
                        \(paramName) = parsedValue
                    } else {
                        throw MCPToolError.invalidArgumentType(name: "\(functionName)", parameterName: "\(paramName)", expectedType: "\(paramType)", actualValue: params["\(paramName)"] ?? "nil")
                    }
                    """
                } else if param.type == "Int" {
                    wrapperMethod += """
                    
                    let \(paramName): \(paramType)
                    if let paramValue = params["\(paramName)"] as? \(paramType) {
                        \(paramName) = paramValue
                    } else if let doubleValue = params["\(paramName)"] as? Double {
                        \(paramName) = \(paramType)(doubleValue)
                    } else if let stringValue = params["\(paramName)"] as? String, let parsedValue = \(paramType)(stringValue) {
                        \(paramName) = parsedValue
                    } else {
                        throw MCPToolError.invalidArgumentType(name: "\(functionName)", parameterName: "\(paramName)", expectedType: "\(paramType)", actualValue: params["\(paramName)"] ?? "nil")
                    }
                    """
                } else {
                    wrapperMethod += """
                    
                    guard let \(paramName) = params["\(paramName)"] as? \(paramType) else {
                        throw MCPToolError.invalidArgumentType(name: "\(functionName)", parameterName: "\(paramName)", expectedType: "\(paramType)", actualValue: params["\(paramName)"] ?? "nil")
                    }
                    """
                }
            }
        }
        
        // Add the function call
        let parameterList = parameterInfos.map { "\($0.name): \($0.name)" }.joined(separator: ", ")
        
        if returnTypeForBlock == "Void" {
            wrapperMethod += """
            
                \(functionName)(\(parameterList))
                return "Function executed successfully"
            }
            """
        } else {
            wrapperMethod += """
            
                return \(functionName)(\(parameterList))
            }
            """
        }
        
        return [
            DeclSyntax(stringLiteral: registrationDecl),
            DeclSyntax(stringLiteral: wrapperMethod)
        ]
    }
}
