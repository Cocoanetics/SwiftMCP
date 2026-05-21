//
//  MCPServerMacro+DispatchGeneration.swift
//  SwiftMCPMacros
//
//  Generates the runtime dispatch tables and metadata properties that
//  `@MCPServer` injects into the annotated type.
//

import Foundation
import SwiftSyntax
import SwiftSyntaxMacros

extension MCPServerMacro {
    // MARK: - Tool dispatch
    static func makeCallToolMethod(
        mcpTools: [(functionName: String, toolName: String)],
        hasAppShortcutsProvider: Bool
    ) -> String {
        let switchCases = renderToolSwitchCases(mcpTools: mcpTools)
        let defaultCase = renderToolDefaultCase(hasAppShortcutsProvider: hasAppShortcutsProvider)

        return """
/// Calls a tool by name with the provided arguments
/// - Parameters:
///   - name: The name of the tool to call
///   - arguments: A dictionary of arguments to pass to the tool
/// - Returns: The result of the tool call
/// - Throws: MCPToolError if the tool doesn't exist or cannot be called
public func callTool(_ name: String, arguments: JSONDictionary) async throws -> (Encodable & Sendable) {
   // Find the tool metadata by name (use the property which reflects any toolNaming transforms)
   guard let metadata = mcpToolMetadata.first(where: { $0.name == name }) ?? mcpToolMetadata(for: name) else {
      throw MCPToolError.unknownTool(name: name)
   }

   // Enrich arguments with default values
   let enrichedArguments = try metadata.enrichArguments(arguments)

   // Call the appropriate wrapper method based on the tool name
   switch name {
\(switchCases)

\(defaultCase)
"""
    }

    private static func renderToolSwitchCases(
        mcpTools: [(functionName: String, toolName: String)]
    ) -> String {
        // Create a callTool method that uses a switch statement to call the appropriate wrapper function
        var switchCases = ""
        for (index, tool) in mcpTools.enumerated() {
            switchCases += "      case \"\(tool.toolName)\":\n"
            switchCases += "         return try await __mcpCall_\(tool.functionName)(enrichedArguments)"
            if index < mcpTools.count - 1 {
                switchCases += "\n"
            }
        }
        return switchCases
    }

    private static func renderToolDefaultCase(hasAppShortcutsProvider: Bool) -> String {
        // The default case consults this instance's __mcpExtensionContributions
        // before falling through to AppShortcuts / unknownTool. Each contribution's
        // dispatcher is the corresponding `Type.<Name>.callTool(_:on:arguments:)`
        // — an unbound static function reference, so no retain cycle.
        let extensionFallback = """
         for contribution in __mcpExtensionContributions {
            if contribution.toolMetadata.contains(where: { $0.name == name }),
               let dispatcher = contribution.toolDispatcher {
               return try await dispatcher(name, self, enrichedArguments)
            }
         }
"""

        var defaultCase = """
      default:
\(extensionFallback)
"""
        if hasAppShortcutsProvider {
            defaultCase += """
         let providerType: MCPAppShortcutsProvider.Type = Self.self
         if let result = try await MCPAppIntentTools.callTool(
            named: name,
            providerType: providerType,
            arguments: enrichedArguments
         ) {
            return result
         }
         throw MCPToolError.unknownTool(name: name)
"""
        } else {
            defaultCase += "         throw MCPToolError.unknownTool(name: name)\n"
        }
        defaultCase += """
   }
}
"""
        return defaultCase
    }

    static func makeToolMetadataProperty(
        mcpTools: [(functionName: String, toolName: String)],
        hasAppShortcutsProvider: Bool,
        isActor: Bool
    ) -> String {
        let metadataArray = mcpTools.map { tool -> String in
            // When server-level toolNaming changes the name, use .renamed() to
            // produce metadata whose .name matches the switch-case strings.
            if tool.toolName != tool.functionName {
                return "__mcpMetadata_\(tool.functionName).renamed(\"\(tool.toolName)\")"
            }
            return "__mcpMetadata_\(tool.functionName)"
        }.joined(separator: ", ")
        let metadataSeed = mcpTools.isEmpty ? "[]" : "[\(metadataArray)]"
        let appShortcutsBlock: String
        if hasAppShortcutsProvider {
            appShortcutsBlock = """
   let providerType: MCPAppShortcutsProvider.Type = Self.self
   let shortcutMetadata = MCPAppIntentTools.toolMetadata(for: providerType)
   for toolMetadata in shortcutMetadata where !metadata.contains(where: { $0.name == toolMetadata.name }) {
      metadata.append(toolMetadata)
   }
"""
        } else {
            appShortcutsBlock = ""
        }

        let metadataIsolation = isActor ? "" : "nonisolated "
        return """
/// Returns an array of all available tool metadata
\(metadataIsolation)public var mcpToolMetadata: [MCPToolMetadata] {
   var metadata: [MCPToolMetadata] = \(metadataSeed)
\(appShortcutsBlock)
   for contribution in __mcpExtensionContributions {
      for m in contribution.toolMetadata where !metadata.contains(where: { $0.name == m.name }) {
         metadata.append(m)
      }
   }
   return metadata
}
"""
    }

    // MARK: - Resource dispatch
    static func makeResourceDeclarations(mcpResources: [String], isActor: Bool) -> [String] {
        var output: [String] = []

        // Add mcpResourceMetadata property
        let resourceMetadataArray = mcpResources
            .map { "__mcpResourceMetadata_\($0)" }
            .joined(separator: ", ")
        let resourceMetadataSeed = mcpResources.isEmpty ? "[]" : "[\(resourceMetadataArray)]"
        let resourceMetadataDocLine = "/// Returns an array of all available resource metadata, "
            + "including contributions from `@MCPExtension`-annotated extensions."
        let metadataIsolation = isActor ? "" : "nonisolated "
        let resourceMetadataProperty = """
\(resourceMetadataDocLine)
\(metadataIsolation)public var mcpResourceMetadata: [MCPResourceMetadata] {
   var metadata: [MCPResourceMetadata] = \(resourceMetadataSeed)
   for contribution in __mcpExtensionContributions {
      for m in contribution.resourceMetadata where !metadata.contains(where: { $0.name == m.name }) {
         metadata.append(m)
      }
   }
   return metadata
}
"""
        output.append(resourceMetadataProperty)

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
        output.append(mcpResourceTemplatesProperty)

        output.append(makeInternalCallResourceMethod(mcpResources: mcpResources))
        output.append(makeCallResourceAsFunctionMethod())
        output.append(makeGetResourceMethod())

        return output
    }

    static func makeInternalCallResourceMethod(mcpResources: [String]) -> String {
        var resourceFunctionSwitchCases = ""
        for (index, funcName) in mcpResources.enumerated() {
            resourceFunctionSwitchCases += "      case \"\(funcName)\":\n"
            resourceFunctionSwitchCases += "         return try await __mcpResourceCall_\(funcName)("
                + "enrichedArguments, requestedUri: requestedUri, "
                + "overrideMimeType: overrideMimeType)"
            if index < mcpResources.count - 1 {
                resourceFunctionSwitchCases += "\n"
            }
        }

        return """
/// Internal helper method for calling resource functions directly
/// - Parameters:
///   - name: The name of the resource function to call
///   - enrichedArguments: Pre-enriched arguments to pass to the resource function
///   - requestedUri: The URI that was requested (for context)
///   - overrideMimeType: Optional MIME type override
/// - Returns: The resource content from the function call
/// - Throws: MCPResourceError if the resource function doesn't exist or cannot be called
internal func __callResourceFunction(
   _ name: String,
   enrichedArguments: JSONDictionary,
   requestedUri: URL,
   overrideMimeType: String?
) async throws -> [MCPResourceContent] {
   // Call the appropriate wrapper method based on the resource name
   switch name {
\(resourceFunctionSwitchCases)
      default:
         for contribution in __mcpExtensionContributions {
            if contribution.resourceMetadata.contains(where: { $0.functionMetadata.name == name }),
               let dispatcher = contribution.resourceDispatcher {
               return try await dispatcher(
                  name, self, enrichedArguments, requestedUri, overrideMimeType
               )
            }
         }
         throw MCPResourceError.notFound(uri: requestedUri.absoluteString)
   }
}
"""
    }

    static func makeCallResourceAsFunctionMethod() -> String {
        return """
/// Calls a resource function by name with the provided arguments (for OpenAPI support)
/// - Parameters:
///   - name: The name of the resource function to call
///   - arguments: The arguments to pass to the resource function
/// - Returns: The result of the resource function execution
/// - Throws: An error if the resource function doesn't exist or cannot be called
public func callResourceAsFunction(
   _ name: String,
   arguments: JSONDictionary
) async throws -> Encodable & Sendable {
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
   let resourceContents = try await __callResourceFunction(
      metadata.functionMetadata.name,
      enrichedArguments: enrichedArguments,
      requestedUri: constructedUri,
      overrideMimeType: metadata.mimeType
   )

   // Return the first content's text or an empty string if no content
   return resourceContents.first?.text ?? ""
}
"""
    }

    static func makeGetResourceMethod() -> String {
        return """
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
      // Convert [String: String] to JSONDictionary
      let sendableParams: JSONDictionary = params.reduce(into: [:]) { result, pair in
         result[pair.key] = .string(pair.value)
      }
      // Enrich arguments. This can throw if required params are missing or types are wrong for a TEMPLATE.
      let enrichedParams = try match.metadata.enrichArguments(sendableParams)

      // Call the internal helper method
      return try await __callResourceFunction(
         match.metadata.functionMetadata.name,
         enrichedArguments: enrichedParams,
         requestedUri: uri,
         overrideMimeType: match.metadata.mimeType
      )
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
    }

}
