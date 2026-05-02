//
//  ExtensionContextDetection.swift
//  SwiftMCPMacros
//
//  Helper for peer macros: determines whether the attached declaration
//  lives inside an `extension` block.
//
//  Uses the macro expansion context's `lexicalContext`, which is the
//  reliable way to inspect surrounding syntax in peer macros (parent
//  pointers on the supplied declaration are not guaranteed). Used by
//  `@MCPTool`, `@MCPResource`, and `@MCPPrompt` to decide whether to emit
//  a stored metadata `let` (illegal in extensions) or fall back to
//  wrapper-only emission for `@MCPExtension` to aggregate.
//

import SwiftSyntax
import SwiftSyntaxMacros

enum MCPMacroContextDetection {
    /// Returns true if the macro is expanding inside an `extension` block.
    static func isInsideExtension(_ context: some MacroExpansionContext) -> Bool {
        for node in context.lexicalContext {
            if node.is(ExtensionDeclSyntax.self) { return true }
            if node.is(ClassDeclSyntax.self) ||
               node.is(StructDeclSyntax.self) ||
               node.is(ActorDeclSyntax.self) ||
               node.is(EnumDeclSyntax.self) ||
               node.is(ProtocolDeclSyntax.self) {
                return false
            }
        }
        return false
    }
}
