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
 
 This macro adds a `mcpTools` computed property to a class or struct,
 which returns an array of all MCP tools defined in that type.
 It also automatically adds the MCPServer protocol conformance.
 */
public struct MCPServerMacro: MemberMacro, ExtensionMacro {
	/**
	 Expands the macro to provide additional members for the declaration.
	 
	 - Parameters:
	 - node: The attribute syntax node
	 - declaration: The declaration syntax
	 - context: The macro expansion context
	 
	 - Returns: An array of member declaration syntax nodes
	 */
	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		// Check if the declaration is a class
		guard declaration.is(ClassDeclSyntax.self) else {
			// If it's a struct or actor, emit a diagnostic with a fix-it
			if let structDecl = declaration.as(StructDeclSyntax.self) {
				let diagnostic = SwiftDiagnostics.Diagnostic(
					node: Syntax(structDecl.structKeyword),
					message: MCPServerDiagnostic.requiresClass(typeName: structDecl.name.text, actualType: "struct"),
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
			} else if let actorDecl = declaration.as(ActorDeclSyntax.self) {
				let diagnostic = SwiftDiagnostics.Diagnostic(
					node: Syntax(actorDecl.actorKeyword),
					message: MCPServerDiagnostic.requiresClass(typeName: actorDecl.name.text, actualType: "actor"),
					fixIts: [
						FixIt(
							message: MCPServerFixItMessage.replaceWithClass(keyword: "actor"),
							changes: [
								.replace(
									oldNode: Syntax(actorDecl.actorKeyword),
									newNode: Syntax(TokenSyntax.keyword(.class))
								)
							]
						)
					]
				)
				context.diagnose(diagnostic)
			}
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
		let serverDescription = documentation.description.isEmpty ? "nil" : "\"\(documentation.description.replacingOccurrences(of: "\"", with: "\\\""))\""
		
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
		
		// Create a computed property that returns an array of MCPTool objects
		let mcpToolsProperty = """
  /// Returns an array of all MCP tools defined in this type
  var mcpTools: [MCPTool] {
   let mirror = Mirror(reflecting: self)
   var metadataArray: [MCPToolMetadata] = []
   
   for child in mirror.children {
      if let metadata = child.value as? MCPToolMetadata,
      child.label?.hasPrefix("__mcpMetadata_") == true {
      metadataArray.append(metadata)
      }
   }
   
   return metadataArray.convertedToTools()
  }
  """
		
		// Create a dictionary property that maps function names to their wrapper methods
		var handlersInitLines: [String] = []
		for funcName in mcpTools {
			handlersInitLines.append("            handlers[\"\(funcName)\"] = self.__mcpCall_\(funcName)")
		}
		
		// Create a callTool method that uses a switch statement to call the appropriate wrapper function
		var switchCases: [String] = []
		for funcName in mcpTools {
			switchCases.append("""
   case "\(funcName)":
      return try __mcpCall_\(funcName)(enrichedArguments)
   """)
		}
		
		let callToolMethod = """
  /// Calls a tool by name with the provided arguments
  /// - Parameters:
  ///   - name: The name of the tool to call
  ///   - arguments: A dictionary of arguments to pass to the tool
  /// - Returns: The result of the tool call
  /// - Throws: MCPToolError if the tool doesn't exist or cannot be called
  func callTool(_ name: String, arguments: [String: Any]) throws -> Any {
   // Find the tool by name
   guard let tool = mcpTools.first(where: { $0.name == name }) else {
      throw MCPToolError.unknownTool(name: name)
   }
   
   // Enrich arguments with default values
   let enrichedArguments = tool.enrichArguments(arguments, forObject: self, functionName: name)
   
   // Call the appropriate wrapper method based on the tool name
   switch name {
   \(switchCases.joined(separator: "\n"))
   default: throw MCPToolError.unknownTool(name: name)
   }
  }
  """
		
		return [
			DeclSyntax(stringLiteral: nameProperty),
			DeclSyntax(stringLiteral: versionProperty),
			DeclSyntax(stringLiteral: descriptionProperty),
			DeclSyntax(stringLiteral: mcpToolsProperty),
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
		// Check if the declaration already conforms to MCPServer
		let inheritedTypes = declaration.inheritanceClause?.inheritedTypes ?? []
		let alreadyConformsToMCPServer = inheritedTypes.contains { type in
			type.type.trimmedDescription == "MCPServer"
		}
		
		// If it already conforms, don't add the conformance again
		if alreadyConformsToMCPServer {
			return []
		}
		
		// Create an extension that adds the MCPServer protocol conformance
		let extensionDecl = try ExtensionDeclSyntax("extension \(type): MCPServer {}")
		
		return [extensionDecl]
	}
}
