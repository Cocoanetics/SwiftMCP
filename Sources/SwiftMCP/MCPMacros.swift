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
/// ```
@attached(peer, names: prefixed(__mcpMetadata_), prefixed(__mcpCall_))
public macro MCPTool(description: String? = nil, isConsequential: Bool = true) = #externalMacro(module: "SwiftMCPMacros", type: "MCPToolMacro")

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
@attached(member, names: named(callTool), named(mcpToolMetadata), named(__mcpServerName), named(__mcpServerVersion), named(__mcpServerDescription), named(mcpResourceMetadata), named(mcpResources), named(mcpStaticResources), named(mcpResourceTemplates), named(getResource), named(__callResourceFunction), named(callResourceAsFunction))
@attached(extension, conformances: MCPServer, MCPToolProviding, MCPResourceProviding)
public macro MCPServer(name: String? = nil, version: String? = nil) = #externalMacro(module: "SwiftMCPMacros", type: "MCPServerMacro")

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
@attached(member, names: named(schemaMetadata))
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
