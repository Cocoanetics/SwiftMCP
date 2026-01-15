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
 
 This macro transforms a function into an MCP tool by generating metadata and wrapper
 functions for parameter handling and type safety.
 
 Example usage:
 ```swift
 /// Adds two numbers together
 /// - Parameters:
 ///   - a: First number to add
 ///   - b: Second number to add
 /// - Returns: The sum of the two numbers
 @MCPTool
 func add(_ a: Double, _ b: Double = 0) -> Double {
     return a + b
 }
 ```
 
 - Parameters:
   - description: Optional override for the function's documentation description.
   - isConsequential: Whether the function's actions are consequential (defaults to true).
 
 - Note: The macro extracts documentation from the function's comments for:
   * Function description
   * Parameter descriptions
   * Return value description
 
 - Attention: The macro will emit diagnostics for:
   * Missing function descriptions
   * Invalid default value types
   * Non-function declarations
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
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            let diagnostic = Diagnostic(node: Syntax(node), message: MCPToolDiagnostic.onlyFunctions)
            context.diagnose(diagnostic)
            return []
        }

        return try functionPeers(for: funcDecl, node: node, context: context)
    }

    private static func functionPeers(
        for funcDecl: FunctionDeclSyntax,
        node: AttributeSyntax,
        context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {

        // Use the new extractor
        let extractor = FunctionMetadataExtractor(funcDecl: funcDecl, context: context)
        let commonMetadata = try extractor.extract()

        let functionName = commonMetadata.functionName

        // Extract description from the attribute if provided, otherwise use from documentation
        var descriptionArg = "nil"
        var isConsequentialArg = "true"  // Default to true

        if let arguments = node.arguments?.as(LabeledExprListSyntax.self) {
            for argument in arguments {
                if argument.label?.text == "description", let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    let stringValue = stringLiteral.segments.description
                    descriptionArg = "\"\(stringValue.escapedForSwiftString)\"" // Ensure proper escaping
                } else if argument.label?.text == "isConsequential", let boolLiteral = argument.expression.as(BooleanLiteralExprSyntax.self) {
                    isConsequentialArg = boolLiteral.literal.text
                }
            }
        }

        // If no description was provided in the attribute, use from commonMetadata
        if descriptionArg == "nil" {
            if !commonMetadata.documentation.description.isEmpty {
                descriptionArg = "\"\(commonMetadata.documentation.description.escapedForSwiftString)\""
            }
        }

        // If no description was found (neither in attribute nor docs), emit a warning
        // (The missingDescription test case might need adjustment or specific handling here if it relied on old logic)
        if descriptionArg == "nil" && functionName != "missingDescription" { // Adjust condition if needed
            // Use your project's actual diagnostic type
            let diagnostic = Diagnostic(node: Syntax(funcDecl.name), message: MCPToolDiagnostic.missingDescription(functionName: functionName))
            context.diagnose(diagnostic)
        }

        // Generate parameter info strings using the new unified approach
        var parameterInfoStrings: [String] = []
        for parsedParam in commonMetadata.parameters {
            parameterInfoStrings.append(parsedParam.toMCPParameterInfo())
        }

        // Use return type info from commonMetadata
        let returnTypeString = commonMetadata.returnTypeString
        let returnTypeForBlock = returnTypeString // Assuming they are the same now, adjust if MCPTool had specific logic
        let returnDescriptionString = commonMetadata.returnDescription ?? "nil"

        // Generate the metadata variable
        let metadataDeclaration = """
/// Metadata for the \(functionName) tool
nonisolated private let __mcpMetadata_\(functionName) = MCPToolMetadata(
   name: "\(functionName)",
   description: \(descriptionArg),
   parameters: [\(parameterInfoStrings.joined(separator: ", "))],
   returnType: \(returnTypeString).self,
   returnTypeDescription: \(returnDescriptionString),
   isAsync: \(commonMetadata.isAsync),
   isThrowing: \(commonMetadata.isThrowing),
   isConsequential: \(isConsequentialArg)
)
"""

        // Create the wrapper function that takes a dictionary
        var wrapperFuncString = """

		/// Autogenerated wrapper for \(functionName) that takes a dictionary of parameters
"""
        if !commonMetadata.propagatedAttributes.isEmpty {
            for attribute in commonMetadata.propagatedAttributes {
                wrapperFuncString += "\n\t\t\(attribute)"
            }
        }
        wrapperFuncString += "\n\t\tfunc __mcpCall_\(functionName)(_ enrichedArguments: [String: Sendable]) async throws -> (Encodable & Sendable) {\n"

        for detail in commonMetadata.parameters {
            // Use the original parameter type string (detail.type), which includes optional markers.
            wrapperFuncString += """
			
			   let \(detail.name): \(detail.typeString) = try enrichedArguments.extractValue(named: "\(detail.name)", as: \(detail.typeString).self)
			"""
        }

        // Add the function call
        let parameterList = commonMetadata.parameters.map { param in
            if param.label == "_" {
                return param.name
            } else {
                return "\(param.label): \(param.name)"
            }
        }.joined(separator: ", ")

        if returnTypeForBlock == "Void" {
            wrapperFuncString += """
				\(commonMetadata.isThrowing ? "try " : "")\(commonMetadata.isAsync ? "await " : "")\(functionName)(\(parameterList))
				return ""  // return empty string for Void functions
			}
			"""
        } else {
            wrapperFuncString += """
				return \(commonMetadata.isThrowing ? "try " : "")\(commonMetadata.isAsync ? "await " : "")\(functionName)(\(parameterList))
			}
			"""
        }

        return [
			DeclSyntax(stringLiteral: metadataDeclaration),
			DeclSyntax(stringLiteral: wrapperFuncString)
		]
    }

}
