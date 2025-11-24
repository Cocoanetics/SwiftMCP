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
 
 - Note: The server description is automatically extracted from the documentation comment unless overridden via the `description` parameter.

 - Parameters:
   - name: The name of the server. Defaults to the declaration name.
   - version: The version of the server. Defaults to "1.0".
   - description: Optional override for the documentation-derived description.
 
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

        var descriptionArg: String? = nil
        if let arguments {
            for argument in arguments {
                if argument.label?.text == "description",
                   let stringLiteral = argument.expression.as(StringLiteralExprSyntax.self) {
                    let stringValue = stringLiteral.segments.description
                    descriptionArg = "\"\(stringValue.escapedForSwiftString)\""
                }
            }
        }

        let serverName = nameArg ?? declaration.as(ClassDeclSyntax.self)?.name.text ?? declaration.as(StructDeclSyntax.self)?.name.text ?? "UnnamedServer"

        let serverVersion = versionArg ?? "1.0"

        // Extract description from leading documentation and allow override via macro argument
        let leadingTrivia = declaration.leadingTrivia.description
        let documentation = Documentation(from: leadingTrivia)
        let serverDescription: String
        if let descriptionArg {
            serverDescription = descriptionArg
        } else if documentation.description.isEmpty {
            serverDescription = "nil"
        } else {
            serverDescription = "\"\(documentation.description.escapedForSwiftString)\""
        }

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

        // Find all functions with the MCPPrompt macro
        var mcpPrompts: [String] = []

        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                for attribute in funcDecl.attributes {
                    if let identifierAttr = attribute.as(AttributeSyntax.self),
                       let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
                       identifier.name.text == "MCPPrompt" {
                        mcpPrompts.append(funcDecl.name.text)
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

            // Note: mcpResources should be implemented by the developer to combine
            // mcpStaticResources with any dynamic resources they want to provide

            // Add mcpResourceTemplates property (only for resources with parameters)
            let mcpResourceTemplatesProperty = """
/// Returns resource templates (resources with parameters)
public var mcpResourceTemplates: [MCPResourceTemplate] {
   get async {
      return mcpResourceMetadata.filter { !$0.parameters.isEmpty }.flatMap { $0.toResourceTemplates() }
   }
}
"""
            declarations.append(DeclSyntax(stringLiteral: mcpResourceTemplatesProperty))

            // Add internal helper method for calling resource functions
            var resourceFunctionSwitchCases = ""
            for (index, funcName) in mcpResources.enumerated() {
                resourceFunctionSwitchCases += "      case \"\(funcName)\":\n"
                resourceFunctionSwitchCases += "         return try await __mcpResourceCall_\(funcName)(enrichedArguments, requestedUri: requestedUri, overrideMimeType: overrideMimeType)"
                if index < mcpResources.count - 1 {
                    resourceFunctionSwitchCases += "\n"
                }
            }

            let internalCallResourceMethod = """
/// Internal helper method for calling resource functions directly
/// - Parameters:
///   - name: The name of the resource function to call
///   - enrichedArguments: Pre-enriched arguments to pass to the resource function
///   - requestedUri: The URI that was requested (for context)
///   - overrideMimeType: Optional MIME type override
/// - Returns: The resource content from the function call
/// - Throws: MCPResourceError if the resource function doesn't exist or cannot be called
internal func __callResourceFunction(_ name: String, enrichedArguments: [String: Sendable], requestedUri: URL, overrideMimeType: String?) async throws -> [MCPResourceContent] {
   // Call the appropriate wrapper method based on the resource name
   switch name {
\(resourceFunctionSwitchCases)
      default:
         throw MCPResourceError.notFound(uri: requestedUri.absoluteString)
   }
}
"""
            declarations.append(DeclSyntax(stringLiteral: internalCallResourceMethod))

            let callResourceAsFunctionMethod = """
/// Calls a resource function by name with the provided arguments (for OpenAPI support)
/// - Parameters:
///   - name: The name of the resource function to call
///   - arguments: The arguments to pass to the resource function
/// - Returns: The result of the resource function execution
/// - Throws: An error if the resource function doesn't exist or cannot be called
public func callResourceAsFunction(_ name: String, arguments: [String: Sendable]) async throws -> Encodable & Sendable {
   // Find the resource metadata by name
   guard let metadata = mcpResourceMetadata.first(where: { $0.functionMetadata.name == name }) else {
      throw MCPResourceError.notFound(uri: "function://\\(name)")
   }
   
   // Enrich arguments with default values using the same logic as tools
   let enrichedArguments = try metadata.enrichArguments(arguments)
   
   // Get the first template (we know there's at least one since this is a function resource)
   guard let template = metadata.uriTemplates.first else {
      throw MCPResourceError.notFound(uri: "function://\\(name)")
   }
   
   // Construct URI from template and parameters
   let constructedUri = try template.constructURI(with: enrichedArguments)
   
   // Call the existing resource wrapper method
   let resourceContents = try await __callResourceFunction(metadata.functionMetadata.name, enrichedArguments: enrichedArguments, requestedUri: constructedUri, overrideMimeType: metadata.mimeType)
   
   // Return the first content's text or an empty string if no content
   return resourceContents.first?.text ?? ""
}
"""
            declarations.append(DeclSyntax(stringLiteral: callResourceAsFunctionMethod))

            let getResourceMethod = """
/// Retrieves a resource by its URI
/// - Parameter uri: The URI of the resource to retrieve
/// - Returns: The resource content if found
/// - Throws: An error if the resource cannot be accessed or is not found
public func getResource(uri: URL) async throws -> [MCPResourceContent] {
   // Find the best matching template across all resources
   var bestMatch: (metadata: MCPResourceMetadata, template: String, paramCount: Int)?
   
   for metadata in mcpResourceMetadata {
      for template in metadata.uriTemplates {
         if let params = uri.extractTemplateVariables(from: template) {
            let paramCount = params.count
            if bestMatch == nil || paramCount > bestMatch!.paramCount {
               bestMatch = (metadata, template, paramCount)
            }
         }
      }
   }
   
   // If we found a match, use it
   if let match = bestMatch {
      let params = uri.extractTemplateVariables(from: match.template) ?? [:]
      // Convert [String: String] to [String: Sendable]
      let sendableParams: [String: Sendable] = params.reduce(into: [:]) { result, pair in
         result[pair.key] = pair.value as Sendable
      }
      // Enrich arguments. This can throw if required params are missing or types are wrong for a TEMPLATE.
      let enrichedParams = try match.metadata.enrichArguments(sendableParams)
      
      // Call the internal helper method
      return try await __callResourceFunction(match.metadata.functionMetadata.name, enrichedArguments: enrichedParams, requestedUri: uri, overrideMimeType: match.metadata.mimeType)
   }
   
   // If no template matched. Calling getNonTemplateResource for URI
   let nonTemplateContents = try await getNonTemplateResource(uri: uri)
   if !nonTemplateContents.isEmpty {
      return nonTemplateContents
   }

   // If getNonTemplateResource returned empty. THROWING notFound for URI
   throw MCPResourceError.notFound(uri: uri.absoluteString)
}
"""
            declarations.append(DeclSyntax(stringLiteral: getResourceMethod))
        }

        // Add prompt related properties and methods if there are MCPPrompts defined
        if !mcpPrompts.isEmpty {
            let promptMetadataArray = mcpPrompts.map { "__mcpPromptMetadata_\($0)" }.joined(separator: ", ")
            let promptMetadataProperty = """
/// Returns an array of all available prompt metadata
nonisolated public var mcpPromptMetadata: [MCPPromptMetadata] {
   return [\(promptMetadataArray)]
}
"""
            declarations.append(DeclSyntax(stringLiteral: promptMetadataProperty))

            var promptSwitchCases = ""
            for (idx, funcName) in mcpPrompts.enumerated() {
                promptSwitchCases += "      case \"\(funcName)\":\n"
                promptSwitchCases += "         return try await __mcpPromptCall_\(funcName)(enrichedArguments)"
                if idx < mcpPrompts.count - 1 { promptSwitchCases += "\n" }
            }

            let callPromptMethod = """
/// Calls a prompt by name with the provided arguments
public func callPrompt(_ name: String, arguments: [String: Sendable]) async throws -> [PromptMessage] {
   guard let metadata = mcpPromptMetadata.first(where: { $0.name == name }) else {
      throw MCPToolError.unknownTool(name: name)
   }
   let enrichedArguments = try metadata.enrichArguments(arguments)
   switch name {
\(promptSwitchCases)
      default:
         throw MCPToolError.unknownTool(name: name)
   }
}
"""
            declarations.append(DeclSyntax(stringLiteral: callPromptMethod))
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

        // Check if the declaration has any MCPPrompt functions
        var hasMCPPrompts = false
        for member in declaration.memberBlock.members {
            if let funcDecl = member.decl.as(FunctionDeclSyntax.self) {
                for attribute in funcDecl.attributes {
                    if let identifierAttr = attribute.as(AttributeSyntax.self),
                       let identifier = identifierAttr.attributeName.as(IdentifierTypeSyntax.self),
                       identifier.name.text == "MCPPrompt" {
                        hasMCPPrompts = true
                        break
                    }
                }
                if hasMCPPrompts { break }
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

        // Check if already conforms to MCPPromptProviding
        let alreadyConformsToPromptProviding = inheritedTypes.contains { type in
            type.type.trimmedDescription == "MCPPromptProviding"
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

        if hasMCPPrompts && !alreadyConformsToPromptProviding {
            protocolsToAdd.append("MCPPromptProviding")
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
