//
//  MCPServerMacro+PromptAndStorage.swift
//  SwiftMCPMacros
//
//  Prompt dispatch and the per-instance `@MCPExtension` contribution
//  storage emitted by `@MCPServer`.
//

import Foundation
import SwiftSyntax

extension MCPServerMacro {
    // MARK: - Prompt dispatch
    static func makePromptDeclarations(mcpPrompts: [String]) -> [String] {
        let promptMetadataArray = mcpPrompts
            .map { "__mcpPromptMetadata_\($0)" }
            .joined(separator: ", ")
        let promptMetadataSeed = mcpPrompts.isEmpty ? "[]" : "[\(promptMetadataArray)]"
        let promptMetadataDocLine = "/// Returns an array of all available prompt metadata, "
            + "including contributions from `@MCPExtension`-annotated extensions."
        let promptMetadataProperty = """
\(promptMetadataDocLine)
nonisolated public var mcpPromptMetadata: [MCPPromptMetadata] {
   var metadata: [MCPPromptMetadata] = \(promptMetadataSeed)
   for contribution in __mcpExtensionContributions {
      for m in contribution.promptMetadata where !metadata.contains(where: { $0.name == m.name }) {
         metadata.append(m)
      }
   }
   return metadata
}
"""

        var promptSwitchCases = ""
        for (idx, funcName) in mcpPrompts.enumerated() {
            promptSwitchCases += "      case \"\(funcName)\":\n"
            promptSwitchCases += "         return try await __mcpPromptCall_\(funcName)(enrichedArguments)"
            if idx < mcpPrompts.count - 1 { promptSwitchCases += "\n" }
        }

        let callPromptMethod = """
/// Calls a prompt by name with the provided arguments
public func callPrompt(
   _ name: String,
   arguments: JSONDictionary
) async throws -> [PromptMessage] {
   guard let metadata = mcpPromptMetadata.first(where: { $0.name == name }) else {
      throw MCPToolError.unknownTool(name: name)
   }
   let enrichedArguments = try metadata.enrichArguments(arguments)
   switch name {
\(promptSwitchCases)
      default:
         for contribution in __mcpExtensionContributions {
            if contribution.promptMetadata.contains(where: { $0.name == name }),
               let dispatcher = contribution.promptDispatcher {
               return try await dispatcher(name, self, enrichedArguments)
            }
         }
         throw MCPToolError.unknownTool(name: name)
   }
}
"""

        return [promptMetadataProperty, callPromptMethod]
    }

    // MARK: - Extension storage
    static func makeExtensionStorageDeclarations(serverTypeName: String) -> [String] {
        let contributionsStorageLine1 = "/// Contributions from `@MCPExtension`-annotated extensions."
        let contributionsStorageLine2 = "/// Populated by `MyServer.<Name>.register(in:)` calls at startup."
        let contributionsStorageDecl = "nonisolated(unsafe) private var __mcpExtensionContributions: "
            + "[MCPExtensionContribution<\(serverTypeName)>] = []"
        let contributionsStorage = """
\(contributionsStorageLine1)
\(contributionsStorageLine2)
\(contributionsStorageDecl)
"""

        let registeredIDsStorage = """
/// IDs of `@MCPExtension` nested types already registered on this instance.
nonisolated(unsafe) private var __mcpRegisteredExtensionIDs: Set<ObjectIdentifier> = []
"""

        let registerExtensionMethod = """
/// Installs an extension's contribution on this server instance.
/// Called by `register(in:)` emitted by `@MCPExtension`. Idempotent on the
/// extension's metatype identity — registering the same extension twice
/// has no effect.
public func __mcpRegisterExtension(
   _ contribution: MCPExtensionContribution<\(serverTypeName)>,
   byID id: ObjectIdentifier
) {
   guard !__mcpRegisteredExtensionIDs.contains(id) else { return }
   __mcpRegisteredExtensionIDs.insert(id)
   __mcpExtensionContributions.append(contribution)
}
"""
        return [contributionsStorage, registeredIDsStorage, registerExtensionMethod]
    }
}
