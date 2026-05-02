//
//  MCPExtensionToolMacro.swift
//  SwiftMCPMacros
//
//  No-op marker for `@MCPExtensionTool`. The SwiftMCPAggregator build plugin
//  is the actual consumer of this attribute — it scans source files for
//  `@MCPExtensionTool` and generates bootstrap code that pushes the tool into
//  `MCPExtensionRegistry`. The macro itself emits no peers because peers
//  inside an extension can only be functions/computed properties; we don't
//  need any here.
//

import SwiftSyntax
import SwiftSyntaxMacros

public struct MCPExtensionToolMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        return []
    }
}
