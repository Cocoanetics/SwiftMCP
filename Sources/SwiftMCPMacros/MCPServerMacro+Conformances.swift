//
//  MCPServerMacro+Conformances.swift
//  SwiftMCPMacros
//
//  Implements the `ExtensionMacro` conformance: emits protocol conformances
//  for `MCPServer`, `MCPToolProviding`, `MCPResourceProviding`, and
//  `MCPPromptProviding` when missing on the annotated declaration.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

extension MCPServerMacro {
    /// Expands the macro to provide protocol conformances for the declaration.
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        let inheritedTypes = declaration.inheritanceClause?.inheritedTypes ?? []
        let alreadyConformsToMCPServer = inheritedTypes.contains { type in
            type.type.trimmedDescription == "MCPServer"
        }
        let alreadyConformsToToolProviding = inheritedTypes.contains { type in
            type.type.trimmedDescription == "MCPToolProviding"
        }
        let alreadyConformsToResourceProviding = inheritedTypes.contains { type in
            type.type.trimmedDescription == "MCPResourceProviding"
        }
        let alreadyConformsToPromptProviding = inheritedTypes.contains { type in
            type.type.trimmedDescription == "MCPPromptProviding"
        }

        // Determine which protocols need to be added
        var protocolsToAdd: [String] = []

        if !alreadyConformsToMCPServer {
            protocolsToAdd.append("MCPServer")
        }

        // Always conform to MCPToolProviding / MCPResourceProviding /
        // MCPPromptProviding so `@MCPExtension`-contributed tools, resources,
        // and prompts can surface at runtime even when the primary type
        // declares none. The macro can't see other files; the safe default
        // is to assume any kind might come from an extension.
        if !alreadyConformsToToolProviding {
            protocolsToAdd.append("MCPToolProviding")
        }
        if !alreadyConformsToResourceProviding {
            protocolsToAdd.append("MCPResourceProviding")
        }
        if !alreadyConformsToPromptProviding {
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
}
