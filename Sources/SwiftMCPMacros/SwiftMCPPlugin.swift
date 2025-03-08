//
//  SwiftMCPPlugin.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 08.03.25.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros

/**
 The main entry point for the Swift MCP compiler plugin.
 
 This struct conforms to `CompilerPlugin` and provides the macros
 that are available in this package.
 */
@main
struct SwiftMCPPlugin: CompilerPlugin {
    /// The macros provided by this plugin
    let providingMacros: [Macro.Type] = [
        MCPFunctionMacro.self,
        MCPToolMacro.self,
    ]
} 