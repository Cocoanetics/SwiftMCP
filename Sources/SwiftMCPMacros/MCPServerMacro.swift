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

 - Note: The server description is automatically extracted from the documentation comment
   unless overridden via the `description` parameter.

 - Parameters:
   - name: The name of the server. Defaults to the declaration name.
   - version: The version of the server. Defaults to "1.0".
   - description: Optional override for the documentation-derived description.

 - Throws: MCPToolError if a tool cannot be found or called

 - Note: The macro can be applied to a `class`, an `actor`, or a `struct`. Pick
         the kind by whether the server has shared mutable *domain* state:
         a stateless server can be a `struct` (trivially `Sendable`); a server
         with shared mutable state should be an `actor` (or a thread-safe
         `class`). The transport/plumbing no longer forces a reference type.
 */
public struct MCPServerMacro: MemberMacro, ExtensionMacro, MemberAttributeMacro {
    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingAttributesFor member: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [AttributeSyntax] {
        _ = node
        _ = context

        guard hasAppShortcutsProvider(declaration: declaration) else { return [] }

        guard let varDecl = member.as(VariableDeclSyntax.self) else { return [] }
        guard varDecl.bindings.count == 1, let binding = varDecl.bindings.first else { return [] }
        guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else { return [] }
        guard identifierPattern.identifier.text == "appShortcuts" else { return [] }

        let alreadyHasBuilder = varDecl.attributes.contains { attribute in
            guard let attributeSyntax = attribute.as(AttributeSyntax.self) else { return false }
            let name = attributeSyntax.attributeName.trimmedDescription
            return name == "AppShortcutsBuilder" || name.hasSuffix(".AppShortcutsBuilder")
        }
        guard !alreadyHasBuilder else { return [] }

        return [
            AttributeSyntax(attributeName: IdentifierTypeSyntax(name: .identifier("AppShortcutsBuilder")))
        ]
    }

    /// Expands the macro to provide additional members for the declaration.
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        let serverArgs = parseServerArguments(node: node, declaration: declaration)
        let hasAppShortcutsProvider = hasAppShortcutsProvider(declaration: declaration)

        let (mcpTools, toolFunctions) = collectToolFunctions(
            declaration: declaration,
            toolNaming: serverArgs.toolNaming
        )
        let (mcpResources, resourceFunctions) = collectResourceFunctions(declaration: declaration)
        let (mcpPrompts, promptFunctions) = collectPromptFunctions(declaration: declaration)

        // Extract the host name for typing the per-instance contributions storage.
        let serverTypeName = declaration.as(ClassDeclSyntax.self)?.name.text
            ?? declaration.as(ActorDeclSyntax.self)?.name.text
            ?? declaration.as(StructDeclSyntax.self)?.name.text
            ?? "Self"

        // Branch the generated code on host kind. Actor hosts keep storage and
        // metadata getters actor-isolated; class hosts keep the original
        // non-isolated layout; struct (value-type) hosts use plain storage with
        // a `mutating` registration method. See `makeExtensionStorageDeclarations`.
        let host: MCPServerHostKind
        if declaration.is(ActorDeclSyntax.self) {
            host = .actorType
        } else if declaration.is(StructDeclSyntax.self) {
            host = .structType
        } else {
            host = .classType
        }

        var declarations: [DeclSyntax] = makeBaseDeclarations(serverArgs: serverArgs)
        declarations.append(contentsOf:
            makeExtensionStorageDeclarations(serverTypeName: serverTypeName, host: host)
                .map { DeclSyntax(stringLiteral: $0) })

        // Always emit the tool machinery: even if no `@MCPTool` is declared
        // in the primary type, `@MCPExtension`-annotated extensions in this
        // or downstream targets may contribute tools at runtime.
        declarations.append(DeclSyntax(stringLiteral: makeCallToolMethod(
            mcpTools: mcpTools,
            hasAppShortcutsProvider: hasAppShortcutsProvider
        )))
        declarations.append(DeclSyntax(stringLiteral: makeToolMetadataProperty(
            mcpTools: mcpTools,
            hasAppShortcutsProvider: hasAppShortcutsProvider,
            host: host
        )))

        // Always emit resource-related machinery: extensions may contribute
        // resources even when the primary type declares none.
        for resourceDecl in makeResourceDeclarations(mcpResources: mcpResources, host: host) {
            declarations.append(DeclSyntax(stringLiteral: resourceDecl))
        }

        // Always emit prompt-related machinery: extensions may contribute
        // prompts even when the primary type declares none.
        for promptDecl in makePromptDeclarations(mcpPrompts: mcpPrompts, host: host) {
            declarations.append(DeclSyntax(stringLiteral: promptDecl))
        }

        // Always emit the nested `Client` type. `@MCPExtension` peer
        // expansions extend `<Type>.Client` with extension-contributed
        // methods, so Client must exist for any `@MCPServer` type.
        // The `generateClient:` parameter is retained on the public API
        // for source-compat with earlier code but is now a no-op.
        _ = serverArgs.generateClient
        let clientType = makeClientType(
            toolFunctions: toolFunctions,
            mcpTools: mcpTools,
            resourceFunctions: resourceFunctions,
            promptFunctions: promptFunctions,
            serverDescription: serverArgs.serverDescriptionText
        )
        declarations.append(DeclSyntax(stringLiteral: clientType))

        return declarations
    }

    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        try expansion(of: node, providingMembersOf: declaration, in: context)
    }

    // MARK: - Helpers used by the main expansion

    static func makeBaseDeclarations(serverArgs: ServerArguments) -> [DeclSyntax] {
        let nameProperty = "private let __mcpServerName = \"\(serverArgs.name)\""
        let versionProperty = "private let __mcpServerVersion = \"\(serverArgs.version)\""
        let descriptionProperty = "private let __mcpServerDescription: String? = \(serverArgs.descriptionLiteral)"
        let titleProperty = "private let __mcpServerTitle: String? = \(serverArgs.titleLiteral)"
        let websiteUrlProperty = "private let __mcpServerWebsiteUrl: String? = \(serverArgs.websiteUrlLiteral)"
        return [
            DeclSyntax(stringLiteral: nameProperty),
            DeclSyntax(stringLiteral: versionProperty),
            DeclSyntax(stringLiteral: descriptionProperty),
            DeclSyntax(stringLiteral: titleProperty),
            DeclSyntax(stringLiteral: websiteUrlProperty)
        ]
    }
}
