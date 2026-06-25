//
//  MCPServerMacro+PromptAndStorage.swift
//  SwiftMCPMacros
//
//  Prompt dispatch and the per-instance `@MCPExtension` contribution
//  storage emitted by `@MCPServer`.
//

import Foundation
import SwiftSyntax

/// The kind of type `@MCPServer` is attached to. Drives the isolation/mutation
/// modifiers on the generated storage and metadata accessors.
///
/// - `actorType`: storage is actor-isolated; the executor serializes access.
/// - `classType`: storage is `nonisolated(unsafe)` and accessors are
///   `nonisolated` — the historical reference-type layout.
/// - `structType`: a value-type server. A `struct` cannot carry
///   `nonisolated(unsafe)` stored properties, and `@MCPExtension`'s
///   `register(in:)` calls `__mcpRegisterExtension` on an immutable parameter, so
///   the contributions live in a small reference-typed box — registration stays
///   non-`mutating` and the server stays `Sendable`.
enum MCPServerHostKind {
    case actorType
    case classType
    case structType

    /// `nonisolated` prefix for the public metadata getters. Class hosts read
    /// `nonisolated(unsafe)` storage; actor and struct hosts read isolated or
    /// plain storage and need no prefix.
    var metadataIsolation: String {
        switch self {
        case .actorType, .structType: return ""
        case .classType: return "nonisolated "
        }
    }
}

extension MCPServerMacro {
    // MARK: - Prompt dispatch
    static func makePromptDeclarations(mcpPrompts: [String], host: MCPServerHostKind) -> [String] {
        let promptMetadataArray = mcpPrompts
            .map { "__mcpPromptMetadata_\($0)" }
            .joined(separator: ", ")
        let promptMetadataSeed = mcpPrompts.isEmpty ? "[]" : "[\(promptMetadataArray)]"
        let promptMetadataDocLine = "/// Returns an array of all available prompt metadata, "
            + "including contributions from `@MCPExtension`-annotated extensions."
        // Class hosts keep the original `nonisolated` getter (reads
        // `nonisolated(unsafe)` storage). Actor hosts drop `nonisolated`
        // so the getter is actor-isolated and can read actor-isolated
        // storage — the executor handles serialization. Struct hosts read
        // plain stored state, so they need no isolation prefix either.
        let metadataIsolation = host.metadataIsolation
        let promptMetadataProperty = """
\(promptMetadataDocLine)
\(metadataIsolation)public var mcpPromptMetadata: [MCPPromptMetadata] {
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
    static func makeExtensionStorageDeclarations(serverTypeName: String, host: MCPServerHostKind) -> [String] {
        if case .structType = host {
            return makeStructExtensionStorage(serverTypeName: serverTypeName)
        }
        return makeReferenceExtensionStorage(serverTypeName: serverTypeName, host: host)
    }

    /// Reference-type (`class` / `actor`) layout.
    ///
    /// - Actor hosts: storage is actor-isolated (no `nonisolated(unsafe)`),
    ///   `__mcpRegisterExtension` is actor-isolated (so the executor serializes
    ///   register / register-while-dispatch automatically), and the matching
    ///   `register(in:)` emitted by `@MCPExtension` is `async`.
    /// - Class hosts: storage stays `nonisolated(unsafe)` and the method is
    ///   declared `async` with a sync body so the same `await
    ///   server.__mcpRegisterExtension(...)` shape compiles. Class `@MCPServer`
    ///   users have always treated registration as setup-time work.
    private static func makeReferenceExtensionStorage(
        serverTypeName: String,
        host: MCPServerHostKind
    ) -> [String] {
        let isActor: Bool
        if case .actorType = host { isActor = true } else { isActor = false }
        let storageIsolation = isActor ? "" : "nonisolated(unsafe) "
        let registerEffects = isActor ? "" : "async "

        let contributionsStorage = """
/// Contributions from `@MCPExtension`-annotated extensions.
/// Populated by `MyServer.<Name>.register(in:)` calls at startup.
\(storageIsolation)private var __mcpExtensionContributions: [MCPExtensionContribution<\(serverTypeName)>] = []
"""

        let registeredIDsStorage = """
/// IDs of `@MCPExtension` nested types already registered on this instance.
\(storageIsolation)private var __mcpRegisteredExtensionIDs: Set<ObjectIdentifier> = []
"""

        let registerExtensionMethod = """
/// Installs an extension's contribution on this server instance.
/// Called by `register(in:)` emitted by `@MCPExtension`. Idempotent on the
/// extension's metatype identity — registering the same extension twice
/// has no effect.
public func __mcpRegisterExtension(
   _ contribution: MCPExtensionContribution<\(serverTypeName)>,
   byID id: ObjectIdentifier
) \(registerEffects){
   guard !__mcpRegisteredExtensionIDs.contains(id) else { return }
   __mcpRegisteredExtensionIDs.insert(id)
   __mcpExtensionContributions.append(contribution)
}
"""
        return [contributionsStorage, registeredIDsStorage, registerExtensionMethod]
    }

    /// Value-type (`struct`) layout. The contributions live in a small
    /// reference-typed box so `__mcpRegisterExtension` is non-`mutating` —
    /// `@MCPExtension`'s `register(in server:)` calls it on an immutable `server`
    /// parameter, which a `mutating` method could not satisfy. The box is
    /// `@unchecked Sendable` (registration is setup-time work, the same contract
    /// as class hosts), so the value-type server stays `Sendable`.
    private static func makeStructExtensionStorage(serverTypeName: String) -> [String] {
        let storageBox = """
/// Reference-typed storage for `@MCPExtension` contributions on this value-type
/// server, so registration need not make the server `mutating`.
private final class __MCPExtensionStorage: @unchecked Sendable {
   var contributions: [MCPExtensionContribution<\(serverTypeName)>] = []
   var registeredIDs: Set<ObjectIdentifier> = []
}
"""

        let boxInstance = "private let __mcpExtensionStorageBox = __MCPExtensionStorage()"

        let contributionsAccessor = """
/// Contributions from `@MCPExtension`-annotated extensions.
private var __mcpExtensionContributions: [MCPExtensionContribution<\(serverTypeName)>] {
   __mcpExtensionStorageBox.contributions
}
"""

        let registerExtensionMethod = """
/// Installs an extension's contribution on this server instance.
/// Called by `register(in:)` emitted by `@MCPExtension`. Idempotent on the
/// extension's metatype identity — registering the same extension twice
/// has no effect.
public func __mcpRegisterExtension(
   _ contribution: MCPExtensionContribution<\(serverTypeName)>,
   byID id: ObjectIdentifier
) async {
   guard !__mcpExtensionStorageBox.registeredIDs.contains(id) else { return }
   __mcpExtensionStorageBox.registeredIDs.insert(id)
   __mcpExtensionStorageBox.contributions.append(contribution)
}
"""
        return [storageBox, boxInstance, contributionsAccessor, registerExtensionMethod]
    }
}
