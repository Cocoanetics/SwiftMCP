//
//  MCPMacros.swift
//  SwiftMCP
//
//  Created by Oliver Drobnik on 08.03.25.
//

import Foundation

/**
 * Macros for the Model Context Protocol (MCP).
 *
 * This file contains macro declarations that are used to automatically
 * generate metadata for functions and classes in the MCP.
 */

/// A macro that automatically extracts parameter information from a function declaration.
/// 
/// Apply this macro to functions that should be exposed to AI models.
/// It will generate metadata about the function's parameters, return type, and description.
///
/// Example:
/// ```swift
/// @MCPFunction(description: "Adds two numbers")
/// func add(a: Int, b: Int) -> Int {
///     return a + b
/// }
/// ```
@attached(peer, names: prefixed(__metadata_))
public macro MCPFunction(description: String? = nil) = #externalMacro(module: "SwiftMCPMacros", type: "MCPFunctionMacro")

/// A macro that adds a `mcpTools` property to a class to aggregate function metadata.
///
/// Apply this macro to classes that contain `@MCPFunction` annotated methods.
/// It will generate a property that returns an array of `MCPTool` objects
/// representing all the functions in the class.
///
/// Example:
/// ```swift
/// @MCPTool
/// class Calculator {
///     @MCPFunction(description: "Adds two numbers")
///     func add(a: Int, b: Int) -> Int {
///         return a + b
///     }
/// }
/// ```
@attached(member, names: named(mcpTools))
public macro MCPTool() = #externalMacro(module: "SwiftMCPMacros", type: "MCPToolMacro") 