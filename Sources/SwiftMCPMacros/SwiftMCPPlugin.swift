//
//  SwiftMCPPlugin.swift
//  SwiftMCPMacros
//
//  Created by Oliver Drobnik on 08.03.25.
//

import SwiftCompilerPlugin
import SwiftSyntaxMacros
import SwiftMCP

/**
 Entry point for the Swift MCP compiler plugin.
 
 This struct conforms to the CompilerPlugin protocol and provides
 the macros available in this package.
 */
@main
public struct SwiftMCPPlugin: CompilerPlugin {
    /// The macros provided by this plugin
    public var providingMacros: [Macro.Type] = [
        MCPFunctionMacro.self,
        MCPToolMacro.self
    ]
} 