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
		
		// Find all functions with the MCPResource macro
		var mcpResources: [String] = []
		
		for member in declaration.memberBlock.members {
			if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
				// Check if the function has the MCPResource macro
				for attribute in funcDecl.attributes {
					if let identifierAttr = attribute.as(AttributeSyntax.self),
					   let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
					   identifier.name.text == "MCPResource" {
						mcpResources.append(funcDecl.name.text)
						break
					}
				}
			}
		}
		
		var declarations: [DeclSyntax] = [
			DeclSyntax(stringLiteral: nameProperty),
			DeclSyntax(stringLiteral: versionProperty),
			DeclSyntax(stringLiteral: descriptionProperty),
		]
		
		// Only add callTool method if there are MCPTools defined
		if !mcpTools.isEmpty {
			// Create a callTool method that uses a switch statement to call the appropriate wrapper function
			var switchCases = ""
			for (index, funcName) in mcpTools.enumerated() {
				switchCases += "      case \"\(funcName)\":\n"
				switchCases += "         return try await __mcpCall_\(funcName)(enrichedArguments)"
				if index < mcpTools.count - 1 {
					switchCases += "\n"
				}
			}
			
			let callToolMethod = """
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
\(switchCases)

      default:
         throw MCPToolError.unknownTool(name: name)
   }
}
"""
			
			declarations.append(DeclSyntax(stringLiteral: callToolMethod))
		}
		
		// Add static mcpToolMetadata property
		if !mcpTools.isEmpty {
			let metadataArray = mcpTools.map { "__mcpMetadata_\($0)" }.joined(separator: ", ")
			let metadataProperty = """
/// Returns an array of all available tool metadata
nonisolated public var mcpToolMetadata: [MCPToolMetadata] {
   return [\(metadataArray)]
}
"""
			declarations.append(DeclSyntax(stringLiteral: metadataProperty))
		}
		
		// Add resource-related properties and methods if there are MCPResources defined
		if !mcpResources.isEmpty {
			// Add mcpResourceMetadata property
			let resourceMetadataArray = mcpResources.map { "__mcpResourceMetadata_\($0)" }.joined(separator: ", ")
			let resourceMetadataProperty = """
/// Returns an array of all available resource metadata
nonisolated public var mcpResourceMetadata: [MCPResourceMetadata] {
   return [\(resourceMetadataArray)]
}
"""
			declarations.append(DeclSyntax(stringLiteral: resourceMetadataProperty))
			
			// Add mcpResources property (for static resources - empty for now)
			let mcpResourcesProperty = """
/// Returns static resources (empty for template-based resources)
public var mcpResources: [MCPResource] {
   get async {
      return []
   }
}
"""
			declarations.append(DeclSyntax(stringLiteral: mcpResourcesProperty))
			
			// Add mcpResourceTemplates property
			let mcpResourceTemplatesProperty = """
/// Returns resource templates generated from MCPResource functions
public var mcpResourceTemplates: [MCPResourceTemplate] {
   get async {
      return mcpResourceMetadata.map { $0.toResourceTemplate() }
   }
}
"""
			declarations.append(DeclSyntax(stringLiteral: mcpResourceTemplatesProperty))
			
			// Add getResource method
			let getResourceMethod = """
/// Retrieves a resource by its URI
/// - Parameter uri: The URI of the resource to retrieve
/// - Returns: The resource content if found
/// - Throws: An error if the resource cannot be accessed
public func getResource(uri: URL) async throws -> [MCPResourceContent] {
   // Try to match against resource templates
   for metadata in mcpResourceMetadata {
      if uri.matches(template: metadata.uriTemplate) {
         // Extract variables after confirming match
         let params = uri.extractTemplateVariables(from: metadata.uriTemplate) ?? [:]
         let enrichedParams = try metadata.enrichArguments(params)
         // Call the appropriate wrapper method
         switch metadata.name {
         case "getServerInfo":
            return try await __mcpResourceCall_getServerInfo(enrichedParams, requestedUri: uri, overrideMimeType: metadata.mimeType)
         case "getUserGreeting":
            return try await __mcpResourceCall_getUserGreeting(enrichedParams, requestedUri: uri, overrideMimeType: metadata.mimeType)
         case "searchUsers":
            return try await __mcpResourceCall_searchUsers(enrichedParams, requestedUri: uri, overrideMimeType: metadata.mimeType)
         case "getFeatureList":
            return try await __mcpResourceCall_getFeatureList(enrichedParams, requestedUri: uri, overrideMimeType: metadata.mimeType)
         default:
            break
         }
      }
   }
   throw MCPResourceError.notFound(uri: uri.absoluteString)
}
"""
			declarations.append(DeclSyntax(stringLiteral: getResourceMethod))
		}
		
		return declarations
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
		
		// Check if the declaration has any MCPResource functions
		var hasMCPResources = false
		for member in declaration.memberBlock.members {
			if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
				for attribute in funcDecl.attributes {
					if let identifierAttr = attribute.as(AttributeSyntax.self),
					   let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
					   identifier.name.text == "MCPResource" {
						hasMCPResources = true
						break
					}
				}
				if hasMCPResources { break }
			}
		}
		
		// Check if the declaration already conforms to MCPToolProviding
		let alreadyConformsToToolProviding = inheritedTypes.contains { type in
			type.type.trimmedDescription == "MCPToolProviding"
		}
		
		// Check if the declaration already conforms to MCPResourceProviding
		let alreadyConformsToResourceProviding = inheritedTypes.contains { type in
			type.type.trimmedDescription == "MCPResourceProviding"
		}
		
		// Determine which protocols need to be added
		var protocolsToAdd: [String] = []
		
		if !alreadyConformsToMCPServer {
			protocolsToAdd.append("MCPServer")
		}
		
		if hasMCPTools && !alreadyConformsToToolProviding {
			protocolsToAdd.append("MCPToolProviding")
		}
		
		if hasMCPResources && !alreadyConformsToResourceProviding {
			protocolsToAdd.append("MCPResourceProviding")
		}
		
		// If we have protocols to add, create a single extension with all needed conformances
		if !protocolsToAdd.isEmpty {
			let protocolList = protocolsToAdd.joined(separator: ", ")
			let extensionDecl = try ExtensionDeclSyntax("extension \(type): \(raw: protocolList) {}")
			return [extensionDecl]
		}
		
		return []
	}
	
	public static func expansion(
		of node: AttributeSyntax,
		providingMembersOf declaration: some DeclGroupSyntax,
		conformingTo protocols: [TypeSyntax],
		in context: some MacroExpansionContext
	) throws -> [DeclSyntax] {
		try expansion(of: node, providingMembersOf: declaration, in: context)
	}
}
