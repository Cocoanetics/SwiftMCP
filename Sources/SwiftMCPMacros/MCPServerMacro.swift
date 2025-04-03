//
//  MCPServerMacro.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftDiagnostics

/**
 Implementation of the MCPServer macro.
 
 This macro adds MCPServer protocol conformance and generates the necessary
 infrastructure for handling MCP tools.
 
 Example usage:
 ```swift
 /// A server that provides calculator functionality
 @MCPServer(
     name: "calculator",
     version: "1.0"
 )
 class CalculatorServer {
     // MCP tool functions go here
 }
 ```
 
 Or with an actor:
 ```swift
 /// A server that provides calculator functionality
 @MCPServer(
     name: "calculator",
     version: "1.0"
 )
 actor CalculatorServer {
     // MCP tool functions go here
 }
 ```
 
 - Note: The server description is automatically extracted from the documentation comment.
 
 - Parameters:
   - name: The name of the server. Defaults to the declaration name.
   - version: The version of the server. Defaults to "1.0".
 
 - Throws: MCPToolError if a tool cannot be found or called
 
 - Attention: This macro can only be applied to reference types (classes or actors).
             Using it on a struct will result in a diagnostic with a fix-it to convert to a class.
 */
public struct MCPServerMacro: MemberMacro, ExtensionMacro {
	/**
	 Expands the macro to provide additional members for the declaration.
	 
	 - Parameters:
	   node: The attribute syntax node
	   declaration: The declaration syntax
	   context: The macro expansion context
	 
	 - Returns: An array of member declaration syntax nodes
	 */
	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		// Check if the declaration is a class or actor
		if let structDecl = declaration.as(StructDeclSyntax.self) {
			let diagnostic = SwiftDiagnostics.Diagnostic(
				node: Syntax(structDecl.structKeyword),
				message: MCPServerDiagnostic.requiresReferenceType(typeName: structDecl.name.text),
				fixIts: [
					FixIt(
						message: MCPServerFixItMessage.replaceWithClass(keyword: "struct"),
						changes: [
							.replace(
								oldNode: Syntax(structDecl.structKeyword),
								newNode: Syntax(TokenSyntax.keyword(.class))
							)
						]
					)
				]
			)
			context.diagnose(diagnostic)
			return []
		}
		
		let arguments = node.arguments?.as(LabeledExprListSyntax.self)
		let nameArg = arguments?.first(where: { $0.label?.text == "name" })?.expression.description.trimmingCharacters(in: .punctuationCharacters)
		let versionArg = arguments?.first(where: { $0.label?.text == "version" })?.expression.description.trimmingCharacters(in: .punctuationCharacters)
		
		let serverName = nameArg ?? declaration.as(ClassDeclSyntax.self)?.name.text ?? declaration.as(StructDeclSyntax.self)?.name.text ?? "UnnamedServer"
		
		let serverVersion = versionArg ?? "1.0"
		
		// Extract description from leading documentation
		let leadingTrivia = declaration.leadingTrivia.description
		let documentation = Documentation(from: leadingTrivia)
		let serverDescription = documentation.description.isEmpty ? "nil" : "\"\(documentation.description.escapedForSwiftString)\""
		
		let nameProperty = "private let __mcpServerName = \"\(serverName)\""
		let versionProperty = "private let __mcpServerVersion = \"\(serverVersion)\""
		let descriptionProperty = "private let __mcpServerDescription: String? = \(serverDescription)"
		
		// Find all functions with the MCPTool macro
		var mcpTools: [String] = []
		
		for member in declaration.memberBlock.members {
			if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
				// Check if the function has the MCPTool macro
				for attribute in funcDecl.attributes {
					if let identifierAttr = attribute.as(AttributeSyntax.self),
					   let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
					   identifier.name.text == "MCPTool" {
						mcpTools.append(funcDecl.name.text)
						break
					}
				}
			}
		}
		
		// Create a callTool method that uses a switch statement to call the appropriate wrapper function
		var switchCases = ""
		for (index, funcName) in mcpTools.enumerated() {
			switchCases += "      case \"\(funcName)\":\n"
			switchCases += "         return try await __mcpCall_\(funcName)(enrichedArguments)"
			if index < mcpTools.count - 1 {
				switchCases += "\n"
			}
		}
		
		let callToolMethod: String
		
		if mcpTools.isEmpty {
			// Simplified version when no tools exist
			callToolMethod = """
/// Calls a tool by name with the provided arguments
/// - Parameters:
///   - name: The name of the tool to call
///   - arguments: A dictionary of arguments to pass to the tool
/// - Returns: The result of the tool call
/// - Throws: MCPToolError if the tool doesn't exist or cannot be called
public func callTool(_ name: String, arguments: [String: Sendable]) async throws -> (Encodable & Sendable) {
   // Try to find the tool in sub-servers
   for server in servers {
      guard let toolProvider = server as? MCPToolProviding, toolProvider.mcpTools.contains(where: { $0.name == name }) else { continue }
      return try await toolProvider.callTool(name, arguments: arguments)
   }
   
   // No tools are defined in this server
   throw MCPToolError.unknownTool(name: name)
}
"""
		} else {
			// Full version with switch statement for when tools exist
			let callToolPrefix = """
/// Calls a tool by name with the provided arguments
/// - Parameters:
///   - name: The name of the tool to call
///   - arguments: A dictionary of arguments to pass to the tool
/// - Returns: The result of the tool call
/// - Throws: MCPToolError if the tool doesn't exist or cannot be called
public func callTool(_ name: String, arguments: [String: Sendable]) async throws -> (Encodable & Sendable) {
   // Find the tool metadata by name
   guard let metadata = mcpToolMetadata(for: name) else {
      throw MCPToolError.unknownTool(name: name)
   }
   
   // Enrich arguments with default values
   let enrichedArguments = try metadata.enrichArguments(arguments)
   
   // Call the appropriate wrapper method based on the tool name
   switch name {

"""

			let callToolSuffix = """

      default:
         // Try to find the tool in sub-servers
         for server in servers {
            guard let toolProvider = server as? MCPToolProviding, toolProvider.mcpTools.contains(where: { $0.name == name }) else { continue }
            return try await toolProvider.callTool(name, arguments: arguments)
         }
         
         throw MCPToolError.unknownTool(name: name)
   }
}
"""
			
			callToolMethod = callToolPrefix + switchCases + callToolSuffix
		}
		
		return [
			DeclSyntax(stringLiteral: nameProperty),
			DeclSyntax(stringLiteral: versionProperty),
			DeclSyntax(stringLiteral: descriptionProperty),
			DeclSyntax(stringLiteral: callToolMethod)
		]
	}
	
	/**
	 Expands the macro to provide protocol conformances for the declaration.
	 
	 - Parameters:
	 - node: The attribute syntax node
	 - declaration: The declaration syntax
	 - type: The type to extend
	 - protocols: The protocols to conform to
	 - context: The macro expansion context
	 
	 - Returns: An array of extension declarations
	 */
	public static func expansion(
		of node: AttributeSyntax,
		attachedTo declaration: some DeclGroupSyntax,
		providingExtensionsOf type: some TypeSyntaxProtocol,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [ExtensionDeclSyntax] {
		var extensions: [ExtensionDeclSyntax] = []
		
		// Check if the declaration already conforms to MCPServer
		let inheritedTypes = declaration.inheritanceClause?.inheritedTypes ?? []
		let alreadyConformsToMCPServer = inheritedTypes.contains { type in
			type.type.trimmedDescription == "MCPServer"
		}
		
		// If it doesn't already conform, add the MCPServer conformance
		if !alreadyConformsToMCPServer {
			let serverExtension = try ExtensionDeclSyntax("extension \(type): MCPServer {}")
			extensions.append(serverExtension)
		}
		
		// Check if the declaration has any MCPTool functions
		var hasMCPTools = false
		for member in declaration.memberBlock.members {
			if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
				for attribute in funcDecl.attributes {
					if let identifierAttr = attribute.as(AttributeSyntax.self),
					   let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
					   identifier.name.text == "MCPTool" {
						hasMCPTools = true
						break
					}
				}
				if hasMCPTools { break }
			}
		}
		
		// Check if the declaration already conforms to MCPToolProviding
		let alreadyConformsToToolProviding = inheritedTypes.contains { type in
			type.type.trimmedDescription == "MCPToolProviding"
		}
		
		// If it has tools and doesn't already conform, add MCPToolProviding conformance
		if hasMCPTools && !alreadyConformsToToolProviding {
			let toolProviderExtension = try ExtensionDeclSyntax("extension \(type): MCPToolProviding {}")
			extensions.append(toolProviderExtension)
		}
		
		return extensions
	}
}
