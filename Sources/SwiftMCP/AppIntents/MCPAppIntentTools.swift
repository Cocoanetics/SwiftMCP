//
//  MCPAppIntentTools.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 19.03.25.
//

#if canImport(AppIntents)
import AppIntents
import Foundation

/// Helpers for exposing AppIntents as MCP tools via AppShortcutsProvider.
@available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *)
public enum MCPAppIntentTools {
    public static func descriptionText(for intentType: any AppIntent.Type) -> String? {
        guard let intentDescription = intentType.description else { return nil }
        let text = String(localized: intentDescription.descriptionText)
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public static func toolMetadata(for providerType: MCPAppShortcutsProvider.Type) -> [MCPToolMetadata] {
        toolInstances(for: providerType).map { $0.mcpToolMetadata }
    }

    public static func callTool(
        named name: String,
        providerType: MCPAppShortcutsProvider.Type,
        arguments: [String: Sendable]
    ) async throws -> (Encodable & Sendable)? {
        guard let tool = toolInstance(named: name, providerType: providerType) else { return nil }
        return try await tool.mcpPerform(arguments: arguments)
    }

    public static func extractReturnValue<T: Encodable & Sendable>(
        from result: any IntentResult,
        as type: T.Type
    ) -> T? {
        _ = type
        let mirror = Mirror(reflecting: result)
        guard let valueChild = mirror.children.first(where: { $0.label == "value" }) else { return nil }
        guard let unwrapped = unwrapOptional(valueChild.value) else { return nil }
        return unwrapped as? T
    }

    private static func toolInstance(
        named name: String,
        providerType: MCPAppShortcutsProvider.Type
    ) -> (any MCPAppIntentTool)? {
        toolInstances(for: providerType).first { $0.mcpToolMetadata.name == name }
    }

    private static func toolInstances(for providerType: MCPAppShortcutsProvider.Type) -> [any MCPAppIntentTool] {
        var toolsByName: [String: any MCPAppIntentTool] = [:]
        for shortcut in providerType.appShortcuts {
            guard let intent = intentInstance(from: shortcut) else { continue }
            guard let tool = intent as? any MCPAppIntentTool else { continue }
            let name = tool.mcpToolMetadata.name
            if toolsByName[name] == nil {
                toolsByName[name] = tool
            }
        }
        return Array(toolsByName.values)
    }

    private static func intentInstance(from shortcut: AppShortcut) -> (any AppIntent)? {
        let mirror = Mirror(reflecting: shortcut)
        if let intent = mirror.children.first(where: { $0.label == "intent" })?.value as? any AppIntent {
            return intent
        }

        if let prepared = mirror.children.first(where: { $0.label == "preparedIntent" })?.value {
            let preparedMirror = Mirror(reflecting: prepared)
            if let intent = preparedMirror.children.first(where: { $0.label == "intent" })?.value as? any AppIntent {
                return intent
            }
        }

        return nil
    }

    private static func unwrapOptional(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first?.value
    }
}
#endif
