//
//  MCPMacros.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/**
 Macros for the Model Context Protocol (MCP).

 This file contains macro declarations that are used to automatically
 generate metadata for functions and classes in the MCP.
 */

/// Naming convention to apply to all tools on an `@MCPServer`.
///
/// When set on `@MCPServer(toolNaming:)`, every `@MCPTool` function name
/// is transformed to the chosen convention **unless** the tool provides an
/// explicit `name:` override (which always wins).
///
/// Example:
/// ```swift
/// @MCPServer(toolNaming: .snakeCase)
/// class MyServer {
///     @MCPTool               // → "list_windows"
///     func listWindows() -> [Window]
///
///     @MCPTool(name: "health") // → "health" (explicit override wins)
///     func checkHealth() -> Status
/// }
/// ```
public enum MCPToolNaming {
    /// Use the Swift function name unchanged (default).
    case functionName
    /// Convert camelCase to snake_case (e.g. `listWindows` → `list_windows`).
    case snakeCase
    /// Convert camelCase to PascalCase (e.g. `listWindows` → `ListWindows`).
    case pascalCase
}

/// A macro that automatically extracts parameter information from a function declaration.
///
/// Apply this macro to functions that should be exposed to AI models.
/// It will generate metadata about the function's parameters, return type, and description.
///
/// Example:
/// ```swift
/// @MCPTool(description: "Adds two numbers")
/// func add(a: Int, b: Int) -> Int {
///     return a + b
/// }
///
/// // With a custom tool name
/// @MCPTool(name: "list_all_windows")
/// func listWindows() -> [Window]  // exposed as "list_all_windows"
///
/// // With hints using OptionSet API (preferred)
/// @MCPTool(hints: [.readOnly])
/// func search(query: String) -> [Result]
///
/// @MCPTool(hints: [.destructive, .openWorld])
/// func deleteAccount(id: String) -> Bool
///
/// @MCPTool(hints: [.idempotent])
/// func updateSetting(key: String, value: String) -> Bool
/// ```
///
/// - Parameters:
///   - name: Optional custom tool name override. If nil, uses the Swift function name.
///   - description: Optional override for the function's documentation description
///   - hints: OptionSet of tool behavior hints (preferred API)
///   - isConsequential: Whether the function's actions are consequential (defaults to true, deprecated - use hints instead)
///   - readOnlyHint: If true, the tool does not modify its environment (deprecated - use hints: [.readOnly])
///   - destructiveHint: If true (and readOnlyHint is false), tool may perform destructive updates (deprecated - use hints: [.destructive])
///   - idempotentHint: If true, calling multiple times with same args has no additional effect (deprecated - use hints: [.idempotent])
///   - openWorldHint: If true, tool may interact with external entities (deprecated - use hints: [.openWorld])
@attached(peer, names: prefixed(__mcpMetadata_), prefixed(__mcpCall_))
public macro MCPTool(
    name: String? = nil,
    description: String? = nil,
    hints: MCPToolHints = [],
    isConsequential: Bool = true,
    readOnlyHint: Bool? = nil,
    destructiveHint: Bool? = nil,
    idempotentHint: Bool? = nil,
    openWorldHint: Bool? = nil
) = #externalMacro(module: "SwiftMCPMacros", type: "MCPToolMacro")

/// A macro that exposes an AppIntent as an MCP tool.
///
/// Apply this macro to AppIntent types to generate tool metadata and a wrapper
/// that maps MCP arguments to intent parameters.
@attached(member, names: named(mcpToolMetadata), named(mcpPerform))
@attached(extension, conformances: MCPAppIntentTool)
public macro MCPAppIntentTool(description: String? = nil, isConsequential: Bool = true) = #externalMacro(module: "SwiftMCPMacros", type: "MCPAppIntentToolMacro")

/// A macro that adds a `mcpTools` property to a class to aggregate function metadata.
///
/// Apply this macro to classes that contain `MCPTool` annotated methods.
/// It will generate a property that returns an array of `MCPTool` objects
/// representing all the functions in the class.
/// It also automatically adds the `MCPServer` protocol conformance.
///
/// Example:
/// ```swift
/// @MCPServer
/// class Calculator {
///     @MCPTool(description: "Adds two numbers")
///     func add(a: Int, b: Int) -> Int {
///         return a + b
///     }
/// }
/// ```
@attached(member, names: named(callTool), named(mcpToolMetadata), named(__mcpServerName), named(__mcpServerVersion), named(__mcpServerDescription), named(mcpResourceMetadata), named(mcpResources), named(mcpStaticResources), named(mcpResourceTemplates), named(getResource), named(__callResourceFunction), named(callResourceAsFunction), named(mcpPromptMetadata), named(callPrompt), named(Client))
@attached(memberAttribute)
@attached(extension, conformances: MCPServer, MCPToolProviding, MCPResourceProviding, MCPPromptProviding)
public macro MCPServer(
    name: String? = nil,
    version: String? = nil,
    description: String? = nil,
    toolNaming: MCPToolNaming = .functionName,
    generateClient: Bool = false
) = #externalMacro(module: "SwiftMCPMacros", type: "MCPServerMacro")

/// A macro that generates schema metadata for a struct.
///
/// Apply this macro to structs to generate metadata about their properties,
/// including property names, types, descriptions, and default values.
/// The macro extracts documentation from comments and generates a hidden
/// metadata property that can be used for validation and serialization.
///
/// Example:
/// ```swift
/// /// A person's contact information
/// @Schema
/// struct ContactInfo {
///     /// The person's full name
///     let name: String
///     
///     /// The person's email address
///     let email: String
///     
///     /// The person's phone number (optional)
///     let phone: String?
/// }
/// ```
@attached(member, names: named(schemaMetadata), named(MCPClientReturn))
@attached(extension, conformances: SchemaRepresentable)
public macro Schema() = #externalMacro(module: "SwiftMCPMacros", type: "SchemaMacro")

/// Macro for validating resource functions against a URI template.
/// 
/// Apply this macro to functions that should be exposed as MCP resources.
/// It will generate metadata about the function's parameters, return type, and URI template.
///
/// Example usage:
/// ```swift
/// @MCPResource("users://{user_id}/profile?locale={lang}")
/// func getUserProfile(user_id: Int, lang: String = "en") -> ProfileResource
/// 
/// @MCPResource(["users://{user_id}/profile", "users://{user_id}"])
/// func getUserProfile(user_id: Int, lang: String = "en") -> ProfileResource
/// ```
@attached(peer, names: prefixed(__mcpResourceMetadata_), prefixed(__mcpResourceCall_))
public macro MCPResource<T>(_ template: T, name: String? = nil, mimeType: String? = nil) = #externalMacro(module: "SwiftMCPMacros", type: "MCPResourceMacro")

@attached(peer, names: prefixed(__mcpPromptMetadata_), prefixed(__mcpPromptCall_))
public macro MCPPrompt(description: String? = nil) = #externalMacro(module: "SwiftMCPMacros", type: "MCPPromptMacro")

/// Marks a function inside an `extension` of an `@MCPServer` type as an MCP tool.
///
/// This is a no-op at macro-expansion time — the SwiftMCPAggregator build-tool
/// plugin scans for this attribute, generates per-target bootstrap code, and
/// pushes the tool into `MCPExtensionRegistry` when the bootstrap function is
/// called at app startup.
///
/// Why a separate macro: `@MCPTool` emits a stored `let` peer, which Swift
/// disallows in extensions. `@MCPExtensionTool` deliberately emits no peers,
/// so it compiles in extension scope. Aggregation is delegated to the build
/// plugin.
///
/// Use:
/// ```swift
/// extension MyServer {
///     @MCPExtensionTool
///     /// Subtract two numbers
///     func subtract(a: Int, b: Int) -> Int { a - b }
/// }
/// ```
///
/// At app startup, call the generated `SwiftMCPBootstrap_<TargetName>.register()`
/// once before serving requests.
@attached(peer)
public macro MCPExtensionTool(name: String? = nil, description: String? = nil) = #externalMacro(module: "SwiftMCPMacros", type: "MCPExtensionToolMacro")
